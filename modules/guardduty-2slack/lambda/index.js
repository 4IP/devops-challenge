'use strict';

const https = require('node:https');

const MIN_SEVERITY = Number(process.env.MIN_SEVERITY || 4);

function severityLabel(severity) {
  if (severity >= 7) return 'HIGH';
  if (severity >= 4) return 'MEDIUM';
  return 'LOW';
}

// GuardDuty findings describe different resource types with different shapes. Only EC2 findings
// have instanceDetails; IAM / S3 / EKS findings do not. Until 2026-10 this function assumed
// instanceDetails existed and crashed on everything else, so non-EC2 findings (including HIGH
// severity S3 exfiltration) were never posted. Summarise whatever is there instead.
function describeResource(resource) {
  if (!resource) return 'unknown';

  const parts = [];
  if (resource.instanceDetails && resource.instanceDetails.instanceId) {
    parts.push(`Instance: ${resource.instanceDetails.instanceId}`);
  }
  if (resource.accessKeyDetails) {
    const { userType, userName, accessKeyId } = resource.accessKeyDetails;
    parts.push(`Principal: ${userType || 'unknown'}/${userName || 'unknown'}${accessKeyId ? ` (${accessKeyId})` : ''}`);
  }
  if (Array.isArray(resource.s3BucketDetails) && resource.s3BucketDetails.length > 0) {
    parts.push(`Bucket: ${resource.s3BucketDetails.map((b) => b.name).join(', ')}`);
  }
  if (resource.eksClusterDetails && resource.eksClusterDetails.name) {
    parts.push(`Cluster: ${resource.eksClusterDetails.name}`);
  }
  if (parts.length === 0) {
    parts.push(`Resource: ${resource.resourceType || 'unknown'}`);
  }
  return parts.join(' | ');
}

function buildMessage(finding) {
  return {
    text: `:rotating_light: GuardDuty ${severityLabel(finding.severity)}: ${finding.title}`,
    blocks: [
      {
        type: 'section',
        text: { type: 'mrkdwn', text: `*${finding.title}*\n${finding.description}` },
      },
      {
        type: 'context',
        elements: [
          {
            type: 'mrkdwn',
            text: `Type: ${finding.type} | Severity: ${finding.severity} | Account: ${finding.accountId} | Region: ${finding.region} | ${describeResource(finding.resource)}`,
          },
        ],
      },
    ],
  };
}

function postToSlack(webhookUrl, payload) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      webhookUrl,
      { method: 'POST', headers: { 'Content-Type': 'application/json' } },
      (res) => {
        res.resume();
        // A 4xx/5xx from Slack used to count as success. Fail instead, so the invocation
        // errors, shows up in the Lambda error metric, and EventBridge retries it.
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`Slack webhook returned HTTP ${res.statusCode}`));
          return;
        }
        resolve();
      },
    );
    req.on('error', reject);
    req.write(JSON.stringify(payload));
    req.end();
  });
}

exports.handler = async (event) => {
  const finding = event.detail;

  if (!finding || typeof finding.severity !== 'number') {
    throw new Error('Event has no GuardDuty finding in detail');
  }

  if (finding.severity < MIN_SEVERITY) {
    return;
  }

  await postToSlack(process.env.SLACK_WEBHOOK_URL, buildMessage(finding));
};

exports.buildMessage = buildMessage;
exports.describeResource = describeResource;
exports.severityLabel = severityLabel;
