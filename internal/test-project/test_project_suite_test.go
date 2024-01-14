package test_project_test

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestTestProject(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "TestProject Suite")
}
