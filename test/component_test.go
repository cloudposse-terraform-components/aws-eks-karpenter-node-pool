package test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/cloudposse/test-helpers/pkg/atmos"
	helper "github.com/cloudposse/test-helpers/pkg/atmos/component-helper"
	awsHelper "github.com/cloudposse/test-helpers/pkg/aws"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/stretchr/testify/assert"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"

	"k8s.io/client-go/dynamic"
)

type ComponentSuite struct {
	helper.TestSuite
}

// waitForReadyCondition polls the given resource until its Ready condition is "True"
// or the timeout expires. Auto Mode resources may take time to reconcile after creation.
func waitForReadyCondition(t *testing.T, dynamicClient dynamic.Interface, gvr schema.GroupVersionResource, name string, timeout time.Duration) {
	t.Helper()
	maxRetries := int(timeout.Seconds() / 10)
	if maxRetries < 1 {
		maxRetries = 1
	}

	retry.DoWithRetry(t, fmt.Sprintf("Waiting for %s Ready condition", name), maxRetries, 10*time.Second, func() (string, error) {
		resource, err := dynamicClient.Resource(gvr).Get(context.Background(), name, metav1.GetOptions{})
		if err != nil {
			return "", fmt.Errorf("failed to get resource %s: %v", name, err)
		}

		conditions, exists, err := unstructured.NestedSlice(resource.Object, "status", "conditions")
		if err != nil {
			return "", fmt.Errorf("failed to get conditions for %s: %v", name, err)
		}
		if !exists {
			return "", fmt.Errorf("%s has no status conditions yet", name)
		}

		for _, condition := range conditions {
			conditionMap, ok := condition.(map[string]interface{})
			if !ok {
				continue
			}
			if conditionMap["type"] == "Ready" {
				status, _ := conditionMap["status"].(string)
				if status == "True" {
					return "Ready", nil
				}
				return "", fmt.Errorf("%s Ready condition is %q, waiting for True", name, status)
			}
		}
		return "", fmt.Errorf("%s has no Ready condition", name)
	})
}

func (s *ComponentSuite) TestBasic() {
	const component = "eks/karpenter-node-pool/basic"
	const stack = "default-test"
	const awsRegion = "us-east-2"

	inputs := map[string]interface{}{}

	defer s.DestroyAtmosComponent(s.T(), component, stack, &inputs)
	options, _ := s.DeployAtmosComponent(s.T(), component, stack, &inputs)
	assert.NotNil(s.T(), options)

	var nodePools map[string]interface{}
	atmos.OutputStruct(s.T(), options, "node_pools", &nodePools)
	assert.NotEmpty(s.T(), nodePools)

	var ec2NodeClasses map[string]interface{}
	atmos.OutputStruct(s.T(), options, "ec2_node_classes", &ec2NodeClasses)
	assert.NotEmpty(s.T(), nodePools)

	clusterOptions := s.GetAtmosOptions("eks/cluster", stack, nil)
	clusrerId := atmos.Output(s.T(), clusterOptions, "eks_cluster_id")

	cluster := awsHelper.GetEksCluster(s.T(), context.Background(), awsRegion, clusrerId)

	config, err := awsHelper.NewK8SClientConfig(cluster)
	assert.NoError(s.T(), err)
	assert.NotNil(s.T(), config)

	dynamicClient, err := dynamic.NewForConfig(config)
	assert.NoError(s.T(), err)
	if err != nil {
		return
	}

	// Define the GroupVersionResource for the EC2NodeClass CRD
	ec2NodeClassesGVR := schema.GroupVersionResource{
		Group:    "karpenter.k8s.aws",
		Version:  "v1",
		Resource: "ec2nodeclasses",
	}

	ec2NodeClassesList, err := dynamicClient.Resource(ec2NodeClassesGVR).Namespace(corev1.NamespaceAll).List(context.Background(), metav1.ListOptions{})
	assert.NoError(s.T(), err)

	assert.Equal(s.T(), len(ec2NodeClassesList.Items), 1)
	ec2NodeClassDefault := ec2NodeClassesList.Items[0]

	assert.Equal(s.T(), ec2NodeClassDefault.GetName(), "default")

	conditions, exists, err := unstructured.NestedSlice(ec2NodeClassDefault.Object, "status", "conditions")
	assert.NoError(s.T(), err)
	assert.True(s.T(), exists)
	for _, condition := range conditions {
		conditionMap := condition.(map[string]interface{})
		assert.Equal(s.T(), conditionMap["status"], "True")
	}

	nodePoolGVR := schema.GroupVersionResource{
		Group:    "karpenter.sh",
		Version:  "v1",
		Resource: "nodepools",
	}

	nodePoolsList, err := dynamicClient.Resource(nodePoolGVR).Namespace(corev1.NamespaceAll).List(context.Background(), metav1.ListOptions{})
	assert.NoError(s.T(), err)

	assert.Equal(s.T(), len(nodePoolsList.Items), 1)
	nodePoolDefault := nodePoolsList.Items[0]

	assert.Equal(s.T(), nodePoolDefault.GetName(), "default")

	conditions, exists, err = unstructured.NestedSlice(nodePoolDefault.Object, "status", "conditions")
	assert.NoError(s.T(), err)
	assert.True(s.T(), exists)
	for _, condition := range conditions {
		conditionMap := condition.(map[string]interface{})
		assert.Equal(s.T(), conditionMap["status"], "True")
	}

	s.DriftTest(component, stack, &inputs)
}

func (s *ComponentSuite) TestAutoMode() {
	const component = "eks/karpenter-node-pool/auto-mode"
	const stack = "default-test"
	const awsRegion = "us-east-2"

	inputs := map[string]interface{}{}

	defer s.DestroyAtmosComponent(s.T(), component, stack, &inputs)
	options, _ := s.DeployAtmosComponent(s.T(), component, stack, &inputs)
	assert.NotNil(s.T(), options)

	var nodePools map[string]interface{}
	atmos.OutputStruct(s.T(), options, "node_pools", &nodePools)
	assert.NotEmpty(s.T(), nodePools)

	clusterOptions := s.GetAtmosOptions("eks/cluster/auto-mode", stack, nil)
	clusterId := atmos.Output(s.T(), clusterOptions, "eks_cluster_id")

	cluster := awsHelper.GetEksCluster(s.T(), context.Background(), awsRegion, clusterId)

	config, err := awsHelper.NewK8SClientConfig(cluster)
	assert.NoError(s.T(), err)
	assert.NotNil(s.T(), config)

	dynamicClient, err := dynamic.NewForConfig(config)
	assert.NoError(s.T(), err)
	if err != nil {
		return
	}

	// Auto Mode uses the eks.amazonaws.com NodeClass CRD instead of
	// karpenter.k8s.aws/EC2NodeClass.
	nodeClassGVR := schema.GroupVersionResource{
		Group:    "eks.amazonaws.com",
		Version:  "v1",
		Resource: "nodeclasses",
	}

	nodeClassList, err := dynamicClient.Resource(nodeClassGVR).Namespace(corev1.NamespaceAll).List(context.Background(), metav1.ListOptions{})
	assert.NoError(s.T(), err)

	// We expect at least the one custom NodeClass we created. Auto Mode also
	// ships built-in NodeClasses, so we look up ours by name rather than count.
	var customNodeClass *unstructured.Unstructured
	for i, item := range nodeClassList.Items {
		if item.GetName() == "custom" {
			customNodeClass = &nodeClassList.Items[i]
			break
		}
	}
	assert.NotNil(s.T(), customNodeClass, "expected to find a NodeClass named 'custom'")

	if customNodeClass != nil {
		// Auto Mode resources may take time to reconcile after creation.
		waitForReadyCondition(s.T(), dynamicClient, nodeClassGVR, "custom", 5*time.Minute)
	}

	nodePoolGVR := schema.GroupVersionResource{
		Group:    "karpenter.sh",
		Version:  "v1",
		Resource: "nodepools",
	}

	nodePoolsList, err := dynamicClient.Resource(nodePoolGVR).Namespace(corev1.NamespaceAll).List(context.Background(), metav1.ListOptions{})
	assert.NoError(s.T(), err)

	// Auto Mode includes built-in pools (general-purpose, system) plus our custom one.
	var customNodePool *unstructured.Unstructured
	for i, item := range nodePoolsList.Items {
		if item.GetName() == "custom" {
			customNodePool = &nodePoolsList.Items[i]
			break
		}
	}
	assert.NotNil(s.T(), customNodePool, "expected to find a NodePool named 'custom'")

	if customNodePool != nil {
		// Auto Mode resources may take time to reconcile after creation.
		waitForReadyCondition(s.T(), dynamicClient, nodePoolGVR, "custom", 5*time.Minute)
	}

	s.DriftTest(component, stack, &inputs)
}

func (s *ComponentSuite) TestEnabledFlag() {
	const component = "eks/karpenter-node-pool/disabled"
	const stack = "default-test"
	s.VerifyEnabledFlag(component, stack, nil)
}

func (s *ComponentSuite) SetupSuite() {
	s.TestSuite.InitConfig()
	s.TestSuite.Config.ComponentDestDir = "components/terraform/eks/karpenter-node-pool"
	s.TestSuite.SetupSuite()
}

func TestRunSuite(t *testing.T) {
	suite := new(ComponentSuite)
	suite.AddDependency(t, "vpc", "default-test", nil)
	suite.AddDependency(t, "eks/cluster", "default-test", nil)
	suite.AddDependency(t, "eks/cluster/auto-mode", "default-test", nil)
	suite.AddDependency(t, "eks/karpenter-controller", "default-test", nil)
	helper.Run(t, suite)
}
