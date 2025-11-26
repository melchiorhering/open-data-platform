from pyspark.sql import SparkSession

# ------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------
# Explicitly use port 80 because your 'just connect' tunnel
# forwards localhost:80 -> Gateway:80.
# Default Spark Connect uses 15002, which won't work here.
CONNECTION_STRING = "sc://sail.localhost:443"


def test_sail_connection():
    print(f"🌊 Connecting to Sail at {CONNECTION_STRING}...")

    try:
        # 1. Initialize the Session
        spark = SparkSession.builder.remote(CONNECTION_STRING).getOrCreate()

        # FIX: Replaced 'spark.sparkContext' (forbidden) with 'spark.version'
        print(f"✅ Session created! Server Version: {spark.version}")

        # 2. Run a simple computation
        print("🚀 Running a simple DataFrame operation...")

        # Create a simple range
        df = spark.range(5).withColumnRenamed("id", "number")

        # Collect results (This triggers the actual gRPC call to the server)
        results = df.collect()

        print("\n📊 Results from Sail:")
        for row in results:
            print(f"   - {row}")

        print("\n🎉 SUCCESS: Your local Python client is talking to Sail in Kind!")

    except Exception as e:
        print("\n❌ ERROR: Could not connect or execute.")
        print("   Troubleshooting Tips:")
        print("   1. Is 'just connect' running in another terminal?")
        print("   2. Is the Sail pod running? (kubectl get pods)")
        print(f"   3. Details: {e}")


if __name__ == "__main__":
    test_sail_connection()
