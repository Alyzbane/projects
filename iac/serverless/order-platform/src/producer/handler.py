"""
This lambda function serves as the entry point for order management operations.
It handles HTTP requests for creating, listing, retrieving, and deleting orders.
The main handler will route requests based on the HTTP method and path, invoking the appropriate function for each operation.
"""
import json
import logging
import os
import uuid
import boto3
from botocore.exceptions import ClientError

logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO,
    datefmt="%Y-%m-%d %H:%M:%S",
)

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE_NAME = os.environ["TABLE_NAME"]
QUEUE_URL = os.environ["QUEUE_URL"]

table = dynamodb.Table(TABLE_NAME)


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def create_order(event):
    body = json.loads(event.get("body") or "{}")
    order_id = body.get("order_id") or str(uuid.uuid4())

    item = {
        "order_id": order_id,
        "status": "PENDING",
        "item_name": body.get("item_name", "Standard Package"),
    }

    try:
        # Prevent silent overwrites of already existing orders
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(order_id)"
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return response(409, {"error": f"Order {order_id} already exists"})
        raise

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({"order_id": order_id}),
    )

    return response(202, {
        "message": "Order accepted and queued for processing",
        "order_id": order_id,
        "status": "PENDING",
    })


def list_orders():
    # Note: In a production scale system, use query pagination or GSI
    result = table.scan()
    return response(200, {"orders": result.get("Items", [])})


def get_order(event):
    order_id = get_order_id(event)
    if not order_id:
        return response(400, {"error": "order_id is required"})

    result = table.get_item(Key={"order_id": order_id})
    item = result.get("Item")

    if not item:
        return response(404, {"error": f"Order {order_id} not found"})

    return response(200, item)


def delete_order(event):
    order_id = get_order_id(event)
    if not order_id:
        return response(400, {"error": "order_id is required"})

    result = table.delete_item(
        Key={"order_id": order_id},
        ReturnValues="ALL_OLD",
    )

    if not result.get("Attributes"):
        return response(404, {"error": f"Order {order_id} not found"})

    return response(200, {"message": f"Order {order_id} successfully cancelled"})


def get_order_id(event):
    path_parameters = event.get("pathParameters") or {}
    return path_parameters.get("order_id")


def handler(event, context):
    http_method = (
        event.get("requestContext", {}).get("http", {}).get("method")
    )

    try:
        if http_method == "POST":
            return create_order(event)
        if http_method == "GET" and not get_order_id(event):
            return list_orders()
        if http_method == "GET":
            return get_order(event)
        if http_method == "DELETE":
            return delete_order(event)

        return response(405, {"error": "Method not allowed"})

    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON body"})
    except Exception as e:
        logging.error(f"Unhandled error: {e}")
        return response(500, {"error": "Internal server error"})