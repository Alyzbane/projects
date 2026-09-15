import json
import logging
import os
import boto3

logging.basicConfig(
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    datefmt='%Y-%m-%d %H:%M:%S'
)

dynamodb = boto3.resource("dynamodb")

def handler(event, context):
    """
    Triggered by messages that have been moved to the Dead Letter Queue (DLQ) after exhausting retry attempts.
    This function reconciles the state of orders in DynamoDB to reflect that processing has failed.
    Args:
        event (dict): The event payload containing the DLQ messages.
        context (LambdaContext): The runtime information of the Lambda function.
    Returns:
        None: This function does not return a value; it updates the DynamoDB table directly. 
    """
    table = dynamodb.Table(os.environ["TABLE_NAME"])

    # Reads messages that exhausted retry limits and dropped into DLQ
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        order_id = body.get("order_id")

        if order_id:
            # Update database status from PENDING to FAILED_PROCESSING for consistency
            table.update_item(
                Key={"order_id": order_id},
                UpdateExpression="SET #s = :status, error_reason = :reason",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={
                    ":status": "FAILED_PROCESSING",
                    ":reason": "Exhausted SQS retries, moved to DLQ"
                }
            )
            logging.info(f"Reconciled order {order_id} state to FAILED_PROCESSING")
