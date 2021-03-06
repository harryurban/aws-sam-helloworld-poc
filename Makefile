.PHONY: help

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

# ------------------------------- #
SAM_TMPL=template.yaml
DEPLOY_TMPL=deployment.yml
STACKNAME=sam-poc-harry
# ------------------------------- #

# ------------------------------- #
# / MAIN SAM COMMANDS #
create: build deploy ## create and deploy sam stack from scratch

rollback: cf-cancel-stackupdate ## rollsback cf stack
status:
	aws cloudformation describe-stacks --stack-name $(STACKNAME)
destroy: cf-cancel-stackupdate  ## destroy sam stack
	@echo "deleting stack via aws cf";
	aws cloudformation delete-stack --stack-name $(STACKNAME)
wipe: destroy ## wipe sam stack and sam state bucket
	aws cloudformation delete-stack --stack-name aws-sam-cli-managed-default
update: create
# MAIN SAM COMMANDS / #
# ------------------------------- #


# ------------------------------- #
# MANUAL STEPS FOR PACKAGED DEPLOYS #
update-via-sam: build package-via-sam sam-deploy-pre-packaged ## trigger a CodeDeploy Deployment for existing stack
update-via-cf: build package-via-cf sam-deploy-pre-packaged ## trigger a CodeDeploy Deployment for existing stack
package-via-sam: ## create deployment.yml manually and upload artifacts to s3 via `sam package`
	sam package --template-file $(SAM_TMPL) --output-template-file $(DEPLOY_TMPL) --s3-bucket $(BUCKET_STACKNAME)

package-via-cf: ## create cf-template-packaged.yaml manually  and upload artifacts to s3 via `aws cf package`
	aws cloudformation package --template-file $(SAM_TMPL) --output-template-file $(DEPLOY_TMPL) --s3-bucket $(BUCKET_STACKNAME)

sam-deploy-pre-packaged:
	sam deploy --template-file $(DEPLOY_TMPL) --stack-name $(STACKNAME)

# / S3 Bucket for deployments #
BUCKET_STACKNAME="sam-deployment-bucket"
create-bucket-stack: ## create the bucket for deployment packages
	aws cloudformation deploy --template-file sam-bucket.yaml --stack-name $(BUCKET_STACKNAME)

destroy-bucket-stack: s3-empty ## destroy the bucket for deployment packages
	aws cloudformation destroy --stack-name $(BUCKET_STACKNAME)
# S3 Bucket for deployments / #

# MANUAL STEPS FOR PACKAGED DEPLOYS #
# ------------------------------- #

# ------------------------------- #
# / LOCAL TESTING #
invoke-hook-local: build ## locally invoke preTrafficHook with Test Event (needs aws credentials)
	sam local invoke --profile default preTrafficHook --event events/prelivehook.json

invoke-function-local: build ## locally invoke HelloWorldFunction with SQS Test Event
	sam local invoke HelloWorldFunction --event events/sqsevent.json
# LOCAL TESTING / #
# ------------------------------- #


# ------------------------------- #
# / SAM SINGLE STEPS #
build:
	sam build
build-container:
	sam build --use-container

deploy:
	sam deploy

# / DEBUG #
build-debug: build debug-build-files
debug-build-files: debug-ls-func-build-files debug-ls-hook-build-files ## list all build files

debug-ls-hook-build-files: # list JsHook build files
	ls -alR .aws-sam/build/JsHook

debug-ls-func-build-files: # list HelloWorld build files
	ls -al .aws-sam/build/HelloWorldFunction

debug-get-artifact-name:
	@echo "$$(awk '/FunctionName: CodeDeployHook_PreLiveHook_HelloWorldFunction/{getline; print}' $(DEPLOY_TMPL) | sed -e 's/\s\{6,\}CodeUri\:\s//')"

debug-dl-artifact-from-s3:
	aws s3 cp $$(awk '/FunctionName: CodeDeployHook_PreLiveHook_HelloWorldFunction/{getline; print}' $(DEPLOY_TMPL) | sed -e 's/\s\{6,\}CodeUri\:\s//') dl_artifacts/
# DEBUG / #


# / HELPERS private functions#
s3-empty:
	aws s3 rm s3://sam-poc-deployment-artifacts --recursive


stop-deploy:
	$(eval DEPLOYMENTID := $(shell aws deploy list-deployments --include-only-statuses "InProgress" | jq ".deployments[0]" --raw-output))
	echo Got Deployment ID: $(DEPLOYMENTID)
	@if [[ $(DEPLOYMENTID) != null ]] ; then aws deploy stop-deployment --deployment-id $(DEPLOYMENTID); fi



cf-cancel-stackupdate:
	@echo "aws cloudformation describe-stacks --stack-name $(STACKNAME) | jq '.Stacks[0].StackStatus' --raw-output | sed -En 's/[A-Z_]+_(IN_PROGRESS)/\1/p'; aws cloudformation cancel-update-stack --stack-name $(STACKNAME)"
	@if [ "$$(aws cloudformation describe-stacks --stack-name $(STACKNAME) | jq '.Stacks[0].StackStatus' --raw-output | sed -En 's/[A-Z_]+_(IN_PROGRESS)/\1/p')" = "IN_PROGRESS" ]; then echo "have to cancel update"; aws cloudformation cancel-update-stack --stack-name $(STACKNAME); fi

# HELPERS / #