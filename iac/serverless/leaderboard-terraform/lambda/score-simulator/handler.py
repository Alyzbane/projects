import json
import random
import boto3
from datetime import datetime, timezone, timedelta

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('leaderboard-scores')

MAX_SCORE = 999999
SCORE_PAD = 7

NAMES = [
    'ShadowNinja', 'BlazeMaster', 'CosmicWolf', 'ThunderStrike',
    'PixelQueen', 'NeonViper', 'FrostByte', 'TurboTank',
    'StarFury', 'IronPulse', 'CyberHawk', 'GhostRider',
    'VortexKing', 'PhoenixRise', 'ZeroGravity', 'MysticRaven',
    'SilverBolt', 'DarkMatter', 'LunarEcho', 'SolarFlare',
    'OmegaWave', 'AlphaStorm', 'BetaShield', 'DeltaForce',
    'GammaRay', 'EpsilonEdge', 'ZetaPrime', 'ThetaBurst',
    'IotaSpark', 'KappaKnight',
]
COUNTRIES = [
    'US', 'US', 'US', 'IN', 'IN', 'UK', 'DE', 'BR',
    'JP', 'KR', 'CA', 'AU', 'FR', 'MX', 'SE',
]

CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Content-Type': 'application/json',
}


def make_inverted(score, player_id):
    inv = MAX_SCORE - int(score)
    return f'{str(inv).zfill(SCORE_PAD)}#{player_id}'


def lambda_handler(event, context):
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS, 'body': ''}

    body = json.loads(event.get('body', '{}'))
    num = min(body.get('players', 15), 50)
    now = datetime.now(timezone.utc)

    # Generate leaderboard IDs for today, this week, and historical
    today = now.strftime("%Y-%m-%d")
    this_week = now.strftime("%Y-W%W")
    yesterday = (now - timedelta(days=1)).strftime("%Y-%m-%d")
    last_week = (now - timedelta(days=7)).strftime("%Y-W%W")

    items = []
    for i in range(num):
        name = NAMES[i % len(NAMES)]
        pid = f"{name.lower()}{i // len(NAMES) if i >= len(NAMES) else ''}"
        country = random.choice(COUNTRIES)

        # All-time: highest scores
        all_score = random.randint(3000, 9999)
        items.append({
            'player_id': pid, 'leaderboard_id': 'all-time',
            'score': all_score, 'inverted_score': make_inverted(all_score, pid),
            'display_name': name, 'games_played': random.randint(10, 100),
            'country': country, 'last_score_at': now.isoformat(),
            'avatar_url': f'https://api.dicebear.com/7.x/pixel-art/svg?seed={pid}',
        })

        # Today: 70% of players active
        if random.random() < 0.7:
            today_score = random.randint(500, 5000)
            items.append({
                'player_id': pid, 'leaderboard_id': f'daily-{today}',
                'score': today_score, 'inverted_score': make_inverted(today_score, pid),
                'display_name': name, 'games_played': random.randint(1, 10),
                'country': country, 'last_score_at': now.isoformat(),
                'avatar_url': f'https://api.dicebear.com/7.x/pixel-art/svg?seed={pid}',
            })

        # This week: 85% of players active
        if random.random() < 0.85:
            week_score = random.randint(1000, 7000)
            items.append({
                'player_id': pid, 'leaderboard_id': f'weekly-{this_week}',
                'score': week_score, 'inverted_score': make_inverted(week_score, pid),
                'display_name': name, 'games_played': random.randint(3, 30),
                'country': country, 'last_score_at': now.isoformat(),
                'avatar_url': f'https://api.dicebear.com/7.x/pixel-art/svg?seed={pid}',
            })

        # Yesterday: for historical data
        if random.random() < 0.5:
            items.append({
                'player_id': pid, 'leaderboard_id': f'daily-{yesterday}',
                'score': random.randint(400, 4000),
                'inverted_score': make_inverted(random.randint(400, 4000), pid),
                'display_name': name, 'games_played': random.randint(1, 8),
                'country': country, 'last_score_at': (now - timedelta(days=1)).isoformat(),
                'avatar_url': f'https://api.dicebear.com/7.x/pixel-art/svg?seed={pid}',
            })

    # Batch write (25 items per batch)
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)

    return {
        'statusCode': 200,
        'headers': CORS,
        'body': json.dumps({
            'players_generated': num,
            'total_records': len(items),
            'leaderboards': ['all-time', f'daily-{today}', f'weekly-{this_week}'],
        }),
    }