import os

from pyspark.sql import SparkSession


kafka_address = os.environ["KAFKA_ADDRESS"]
kafka_port = os.getenv("KAFKA_PORT", "9092")
kafka_topic = os.getenv("KAFKA_TOPIC", "listen_events")

spark = SparkSession.builder.appName("Kafka connectivity validation").getOrCreate()

try:
    kafka_stream = (
        spark.read
        .format("kafka")
        .option("kafka.bootstrap.servers", f"{kafka_address}:{kafka_port}")
        .option("subscribe", kafka_topic)
        .option("startingOffsets", "latest")
        .option("endingOffsets", "latest")
        .load()
    )
    kafka_stream.select("topic").distinct().show(truncate=False)
    print(f"Kafka metadata validation passed for {kafka_address}:{kafka_port}")
finally:
    spark.stop()