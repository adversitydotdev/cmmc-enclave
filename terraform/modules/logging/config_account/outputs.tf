output "recorder_names" {
  description = "Recorder name by region."
  value       = { for r, v in aws_config_configuration_recorder.this : r => v.name }
}
