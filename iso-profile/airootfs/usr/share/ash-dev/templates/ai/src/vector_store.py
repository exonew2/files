from qdrant_client import QdrantClient
from qdrant_client.models import VectorParams, Distance


class VectorStore:
    def __init__(self, host: str = "localhost", port: int = 6333):
        self.client = QdrantClient(host=host, port=port)

    def create_collection(self, name: str, size: int = 768):
        self.client.create_collection(
            collection_name=name,
            vectors_config=VectorParams(size=size, distance=Distance.COSINE),
        )

    def upsert(self, collection: str, points: list):
        self.client.upsert(collection_name=collection, points=points)

    def search(self, collection: str, vector: list, limit: int = 5):
        return self.client.search(
            collection_name=collection,
            query_vector=vector,
            limit=limit,
        )
