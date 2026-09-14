# Scores table (PK player_id / SK leaderboard_id) with the
# leaderboard-rank-index GSI used for the inverted-score ranking pattern.
resource "aws_dynamodb_table" "scores" {
  name         = "leaderboard-scores"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "player_id"
  range_key    = "leaderboard_id"

  attribute {
    name = "player_id"
    type = "S"
  }

  attribute {
    name = "leaderboard_id"
    type = "S"
  }

  attribute {
    name = "inverted_score"
    type = "S"
  }

  global_secondary_index {
    name            = "leaderboard-rank-index"
    hash_key        = "leaderboard_id"
    range_key       = "inverted_score"
    projection_type = "ALL"
  }

  tags = local.tags
}

resource "aws_dynamodb_table" "snapshots" {
  name         = "leaderboard-snapshots"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "snapshot_id"
  range_key    = "rank"

  attribute {
    name = "snapshot_id"
    type = "S"
  }

  attribute {
    name = "rank"
    type = "N"
  }

  tags = local.tags
}
