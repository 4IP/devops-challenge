output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "event_rule_arn" {
  value = aws_cloudwatch_event_rule.findings.arn
}

output "undelivered_queue_arn" {
  description = "Dead-letter queue for findings EventBridge could not deliver to the Lambda."
  value       = aws_sqs_queue.undelivered.arn
}
