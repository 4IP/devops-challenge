# One SNS topic per team/environment that CloudWatch alarms publish to.
#
# Why a plain topic and not the guardduty-2slack Lambda: CloudWatch -> SNS -> Chatbot is fully
# managed, costs nothing, and gives email as a second channel so an alert is not lost when Slack
# is the only subscriber and nobody is looking at it (what happened on 2026-10-13).
#
# The topic is intentionally not KMS-encrypted: CloudWatch alarms cannot publish to a topic that
# uses the AWS-managed SNS key, and a CMK with a key policy is more than this alert path needs
# (the payload is alarm metadata, no customer data).

resource "aws_sns_topic" "this" {
  name = var.name

  tags = var.tags
}

data "aws_iam_policy_document" "topic" {
  statement {
    sid     = "AllowCloudWatchAlarms"
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.this.arn]
  }
}

resource "aws_sns_topic_policy" "this" {
  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_endpoints)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- Slack via AWS Chatbot (optional) ------------------------------------------------------------

data "aws_iam_policy_document" "chatbot_assume" {
  count = var.slack == null ? 0 : 1

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  count = var.slack == null ? 0 : 1

  name               = "${var.name}-chatbot"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume[0].json

  tags = var.tags
}

# Notification-only: Chatbot needs to read the alarm to render it. No write actions, no CLI
# commands from Slack (guardrail_policy_arns below pins the ceiling to read-only as well).
data "aws_iam_policy_document" "chatbot" {
  count = var.slack == null ? 0 : 1

  statement {
    sid    = "DescribeAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "chatbot" {
  count = var.slack == null ? 0 : 1

  name   = "${var.name}-chatbot"
  role   = aws_iam_role.chatbot[0].id
  policy = data.aws_iam_policy_document.chatbot[0].json
}

resource "aws_chatbot_slack_channel_configuration" "this" {
  count = var.slack == null ? 0 : 1

  configuration_name = var.name
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack.team_id
  slack_channel_id   = var.slack.channel_id
  sns_topic_arns     = [aws_sns_topic.this.arn]
  logging_level      = "ERROR"

  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  tags = var.tags
}
