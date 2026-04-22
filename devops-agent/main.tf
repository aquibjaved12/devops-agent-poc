# # ----------------------------
# # IAM ROLE - AGENT
# # ----------------------------
# resource "aws_iam_role" "agent_role" {
#   name = "DevOpsAgentRole-AgentSpace"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Principal = {
#         Service = "devopsagent.amazonaws.com"
#       },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "agent_policy" {
#   role       = aws_iam_role.agent_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
# }

# # ----------------------------
# # IAM ROLE - OPERATOR
# # ----------------------------
# resource "aws_iam_role" "operator_role" {
#   name = "DevOpsAgentRole-WebappAdmin"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Principal = {
#         Service = "devopsagent.amazonaws.com"
#       },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "operator_policy" {
#   role       = aws_iam_role.operator_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
# }

# # ----------------------------
# # WAIT (IAM PROPAGATION)
# # ----------------------------
# resource "time_sleep" "wait_iam" {
#   depends_on = [
#     aws_iam_role.agent_role,
#     aws_iam_role.operator_role
#   ]

#   create_duration = "30s"
# }

# # ----------------------------
# # AGENT SPACE
# # ----------------------------
resource "awscc_devopsagent_agent_space" "agent_space" {
  #   depends_on = [time_sleep.wait_iam]

  name = var.agent_space_name

}

# # ----------------------------
# # ACCOUNT ASSOCIATION
# # ----------------------------
# data "aws_caller_identity" "current" {}

# # resource "awscc_devopsagent_association" "assoc" {
# #   agent_space_id = awscc_devopsagent_agent_space.agent_space.id
# #   account_id     = data.aws_caller_identity.current.account_id
# # }

