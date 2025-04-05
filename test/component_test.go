package test

import (
	"context"
	"fmt"
	"testing"
	helper "github.com/cloudposse/test-helpers/pkg/atmos/component-helper"
	awsHelper "github.com/cloudposse/test-helpers/pkg/aws"
	"github.com/cloudposse/test-helpers/pkg/atmos"
	"github.com/stretchr/testify/assert"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

	"k8s.io/client-go/dynamic"
)

type ComponentSuite struct {
	helper.TestSuite
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
	if err != nil {
		panic(fmt.Errorf("failed to create dynamic client: %v", err))
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
	suite.AddDependency(t, "eks/karpenter-controller", "default-test", nil)
	helper.Run(t, suite)
}
