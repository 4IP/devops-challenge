'use strict';

const { test } = require('node:test');
const assert = require('node:assert');

const { buildMessage, describeResource, severityLabel } = require('../lambda/index');
const ec2Finding = require('../events/ec2-ssh-bruteforce.json');
const iamFinding = require('../events/iam-anomalous-behavior.json');
const s3Finding = require('../events/s3-anomalous-exfiltration.json');

test('severityLabel maps GuardDuty severities', () => {
  assert.strictEqual(severityLabel(8), 'HIGH');
  assert.strictEqual(severityLabel(5), 'MEDIUM');
  assert.strictEqual(severityLabel(2), 'LOW');
});

test('buildMessage includes the finding title and instance', () => {
  const message = buildMessage(ec2Finding.detail);

  assert.match(message.text, /SSH brute force/);
  assert.match(message.blocks[1].elements[0].text, /i-0a1b2c3d4e5f60789/);
});

// Regression: these two threw "Cannot read properties of undefined (reading 'instanceId')"
// and were never posted to Slack.
test('buildMessage handles IAM findings without instanceDetails', () => {
  const message = buildMessage(iamFinding.detail);

  assert.match(message.text, /MEDIUM/);
  assert.match(message.blocks[1].elements[0].text, /IAMUser\/claims-reports-uploader/);
});

test('buildMessage handles S3 findings and names the bucket', () => {
  const message = buildMessage(s3Finding.detail);

  assert.match(message.text, /HIGH/);
  assert.match(message.blocks[1].elements[0].text, /acme-claims-reports-prod/);
  assert.match(message.blocks[1].elements[0].text, /claims-reports-uploader/);
});

test('every sample event renders without throwing', () => {
  for (const event of [ec2Finding, iamFinding, s3Finding]) {
    assert.doesNotThrow(() => buildMessage(event.detail), event.detail.type);
  }
});

test('describeResource falls back to the resource type', () => {
  assert.strictEqual(describeResource({ resourceType: 'Container' }), 'Resource: Container');
  assert.strictEqual(describeResource(undefined), 'unknown');
});
