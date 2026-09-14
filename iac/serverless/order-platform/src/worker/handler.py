import json
import logging
import os
import boto3

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO,
    datefmt="%Y-%m-%d %H:%M:%S",
)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    """
    Processes incoming order messages from SQS.
    Uses 'ReportBatchItemFailures' so only failed messages are retried/DLQ-routed.
    """
    batch_item_failures = []

    for record in event.get("Records", []):
        order_id = None
        try:
            body = json.loads(record["body"])
            order_id = body.get("order_id")

            if not order_id:
                raise ValueError("Payload missing required 'order_id'")

            logging.info(f"Processing order: {order_id}")

            # Idempotent state transition
            table.update_item(
                Key={"order_id": order_id},
                UpdateExpression="SET #s = :status",
                ConditionExpression="attribute_exists(order_id)",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={":status": "COMPLETED"},
            )

        except Exception as e:
            logging.error(f"Failed processing message {record.get('messageId')}: {str(e)}")
            # Identify individual message failure back to SQS
            batch_item_failures.append({"itemIdentifier": record["messageId"]})

    return {"batchItemFailures": batch_item_failures}