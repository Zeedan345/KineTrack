import json

with open('goodsquat_training_data.json', 'r') as f:
    workout_data = json.load(f)
    for frame in workout_data["frames"]:
        print(frame["landmarks"]["left_hip"])  # Example: print left hip landmark data