import os
import paho.mqtt.client as mqtt
import subprocess
import sys

# --- Configuration ---
# IMPORTANT: Change this to the IP address or hostname of your MQTT broker.
MQTT_BROKER = os.getenv("AWSIP", "localhost")
MQTT_PORT = int(os.getenv("AWSPORT", 1883))
# Topic to subscribe to. Your watch should publish commands to this topic.
MQTT_TOPIC = (os.getenv("HS_STDIN_TOPIC", "commands/macbook/hammerspoon/in")
OUTPUT_TOPIC = (os.getenv("HS_STDOUT_TOPIC", "commands/macbook/hammerspoon/out"))

# --- MQTT Client Logic ---

def on_connect(client, userdata, flags, rc):
    """Callback for when the client connects to the broker."""
    if rc == 0:
        print(f"Successfully connected to MQTT Broker at {MQTT_BROKER}")
        # Subscribe to the topic once connected
        client.subscribe(MQTT_TOPIC)
    else:
        print(f"Failed to connect, return code {rc}\n")
        sys.exit(1) # Exit if connection fails

def on_subscribe(client, userdata, mid, granted_qos):
    """Callback for when the client successfully subscribes to a topic."""
    print(f"Subscribed to topic: {MQTT_TOPIC}")

def on_message(client, userdata, msg):
    """Callback for when a message is received from the broker."""
    command = msg.payload.decode()
    print(f"Received command: '{command}'")

    # Construct the command to be executed by Hammerspoon CLI
    # This calls the global function `handleRemoteCommand` we added to init.lua
    hs_command = f'handleRemoteCommand("{command}")'

    try:
        # Execute the command using the `hs` CLI tool
        # We use subprocess.run for better security and process management
        result = subprocess.run(
            ['hs', '-c', hs_command],
            capture_output=True,
            text=True,
            check=True  # This will raise an exception if hs returns a non-zero exit code
        )
        if result.stdout:
            print(f"Hammerspoon stdout: {result.stdout.strip()}")
        if result.stderr:
            print(f"Hammerspoon stderr: {result.stderr.strip()}")
    except FileNotFoundError:
        print("Error: 'hs' command not found. Make sure Hammerspoon is installed and in your PATH.")
    except subprocess.CalledProcessError as e:
        print(f"Error executing Hammerspoon command: {e}")
        print(f"Stderr: {e.stderr.strip()}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def main():
    """Main function to set up and run the MQTT client."""
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_message = on_message

    print("Attempting to connect to MQTT broker...")
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
    except Exception as e:
        print(f"Could not connect to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}. Please check the address and ensure the broker is running.")
        print(f"Error: {e}")
        sys.exit(1)

    # loop_forever() is a blocking call that processes network traffic,
    # dispatches callbacks, and handles reconnecting.
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        print("\nDisconnecting from MQTT broker.")
        client.disconnect()

if __name__ == "__main__":
    main()
