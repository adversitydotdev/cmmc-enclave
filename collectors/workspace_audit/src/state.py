"""Per-application cursor and seen-event set, one DynamoDB item per application."""
import gzip
import json


class DynamoState:
    """Item: application (S, key), cursor (S, RFC3339 high-water mark), seen (B, gzip JSON list)."""

    def __init__(self, client, table):
        self.client = client
        self.table = table

    def get(self, app):
        item = self.client.get_item(
            TableName=self.table, Key={"application": {"S": app}}, ConsistentRead=True
        ).get("Item")
        if not item:
            return None
        seen = json.loads(gzip.decompress(item["seen"]["B"])) if "seen" in item else []
        return {"cursor": item["cursor"]["S"], "seen": seen}

    def put(self, app, cursor, seen):
        self.client.put_item(
            TableName=self.table,
            Item={
                "application": {"S": app},
                "cursor": {"S": cursor},
                "seen": {"B": gzip.compress(json.dumps(sorted(seen)).encode(), mtime=0)},
            },
        )
