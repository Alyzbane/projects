import json
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
scores_table = dynamodb.Table('leaderboard-scores')
snapshots_table = dynamodb.Table('leaderboard-snapshots')

CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST,GET,OPTIONS',
    'Content-Type': 'application/json',
}


def take_snapshot(leaderboard_id, top_n=50):
    now_iso = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    snapshot_id = f'{leaderboard_id}#{now_iso}'

    resp = scores_table.query(
        IndexName='leaderboard-rank-index',
        KeyConditionExpression=Key('leaderboard_id').eq(leaderboard_id),
        ScanIndexForward=True,
        Limit=top_n,
    )

    written = 0
    for rank, item in enumerate(resp.get('Items', []), start=1):
        snapshots_table.put_item(Item={
            'snapshot_id': snapshot_id,
            'rank': rank,
            'player_id': item.get('player_id'),
            'display_name': item.get('display_name', ''),
            'score': int(item.get('score', 0)),
            'snapshot_at': now_iso,
        })
        written += 1

    return {'snapshot_id': snapshot_id, 'players_saved': written}


def lambda_handler(event, context):
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS, 'body': ''}

    body = json.loads(event.get('body', '{}'))
    lb_id = body.get('leaderboard_id', 'all-time')
    top_n = min(int(body.get('top_n', 50)), 100)

    result = take_snapshot(lb_id, top_n)
    return {
        'statusCode': 200,
        'headers': CORS,
        'body': json.dumps(result, default=str),
    }