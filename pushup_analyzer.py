import json
from exercise_analyzer import ExerciseAnalyzer

class PushupAnalyzer(ExerciseAnalyzer):
    """
    Analyzes a stream of pose landmarks to provide feedback on push-up form.
    Inherits from the abstract ExerciseAnalyzer class.
    """
    def __init__(self):
        super().__init__()
        # --- Push-up Specific State Tracking ---
        self.stage = "up" # Start in the 'up' position
        self.last_feedback = ""
        self.min_angle_in_rep = 180

        # --- Frame Buffer for State Change ---
        self.FRAME_BUFFER = 4
        self.up_frames = 0
        self.down_frames = 0

        # --- Timers for Tempo ---
        self.rep_start_time = 0

        # --- Form Thresholds (Tunable) ---
        self.depth_threshold_angle = 100      # Elbow angle must be less than this for a good rep
        self.rep_threshold = 150              # Single threshold to distinguish up/down phases
        self.body_straight_angle_min = 150    # Angle of shoulder-hip-ankle
        self.elbow_flare_angle_max = 80       # Angle of hip-shoulder-elbow
        self.rep_too_fast_seconds = 1.0

    def process_frame(self, frame_data):
        """
        Processes a single frame of landmark data for push-up analysis.
        """
        self.frame_count += 1
        landmarks = frame_data['landmarks']
        current_time = frame_data['relative_time']
        feedback_this_frame = []

        try:
            # --- Get key landmarks using the helper from the base class ---
            shoulder = self.get_landmark(landmarks, 'right_shoulder')
            elbow = self.get_landmark(landmarks, 'right_elbow')
            wrist = self.get_landmark(landmarks, 'right_wrist')
            hip = self.get_landmark(landmarks, 'right_hip')
            ankle = self.get_landmark(landmarks, 'right_ankle')

            # --- Calculate all relevant angles for this frame ---
            elbow_angle = self.calculate_angle(shoulder, elbow, wrist)
            body_angle = self.calculate_angle(shoulder, hip, ankle)
            elbow_flare_angle = self.calculate_angle(hip, shoulder, elbow)

            # --- 1. Body Straightness Check ---
            if body_angle < self.body_straight_angle_min:
                feedback = "Keep your back straight!"
                if self.last_feedback != feedback:
                    feedback_this_frame.append(feedback)
                    self.last_feedback = feedback
            else:
                self.last_feedback = ""

            # --- 2. Elbow Flare Check ---
            if elbow_flare_angle > self.elbow_flare_angle_max:
                feedback_this_frame.append("Tuck your elbows in a bit!")
            
            # --- 3. Rep Counting, Depth, and State Logic with Frame Buffer ---
            if elbow_angle < self.rep_threshold:
                self.down_frames += 1
                self.up_frames = 0 # Reset the other counter
            else:
                self.up_frames += 1
                self.down_frames = 0 # Reset the other counter
            
            # A rep begins when the user has been 'down' for enough frames.
            if self.stage == 'up' and self.down_frames >= self.FRAME_BUFFER:
                self.stage = 'down'
                self.rep_start_time = current_time
                self.min_angle_in_rep = elbow_angle # Start tracking the minimum angle

            # While in the 'down' phase, continuously track the lowest point.
            elif self.stage == 'down':
                self.min_angle_in_rep = min(self.min_angle_in_rep, elbow_angle)
                
                # A rep attempt ends when the user has been 'up' for enough frames.
                if self.up_frames >= self.FRAME_BUFFER:
                    self.stage = 'up'
                    
                    # --- 4. Depth Check (at the end of the rep) ---
                    if self.min_angle_in_rep > self.depth_threshold_angle:
                        feedback_this_frame.append("Go deeper on your push-ups!")
                    else:
                        # Only count the rep if the depth was good.
                        self.rep_count += 1
                    
                    # --- 5. Time of Push-up (Tempo Check) ---
                    rep_duration = current_time - self.rep_start_time
                    if rep_duration < self.rep_too_fast_seconds and self.rep_start_time > 0:
                        feedback_this_frame.append("Slow down your reps!")

                    # Reset trackers for the next rep
                    self.rep_start_time = 0
                    self.min_angle_in_rep = 180

            # Add new, unique feedback to the session log
            unique_feedback_in_log = set(self.feedback_log)
            for item in feedback_this_frame:
                if item not in unique_feedback_in_log:
                    self.feedback_log.append(item)
                    unique_feedback_in_log.add(item)
                    
            return feedback_this_frame

        except KeyError as e:
            return []
        except Exception as e:
            return [f"An error occurred: {e}"]

# --- Example Usage ---
if __name__ == '__main__':
    json_file_path = 'goodpushup_training_data.json'
    workout_data = None

    print(f"--- Attempting to load workout data from '{json_file_path}' ---")
    
    try:
        with open(json_file_path, 'r') as f:
            workout_data = json.load(f)
        print("[SUCCESS] Loaded workout data.")
    except FileNotFoundError:
        print(f"\n[ERROR] The file '{json_file_path}' was not found.")
        print("Please ensure the JSON file is in the same directory as this script.")
        exit() # Exit the script if the file doesn't exist
    except json.JSONDecodeError:
        print(f"\n[ERROR] The file '{json_file_path}' is not a valid JSON file.")
        print("Please check the file for formatting errors.")
        exit()

    # Instantiate the specific push-up analyzer
    analyzer = PushupAnalyzer()
    
    print("\n--- Processing a full workout clip frame-by-frame ---")

    # Loop through each frame in the provided data
    if workout_data and "frames" in workout_data:
        for i, frame in enumerate(workout_data["frames"]):
            feedback = analyzer.process_frame(frame)
            if feedback:
                print(f"Frame {i+1}: Feedback -> {feedback}")
    else:
        print("[WARNING] No frames found in the JSON data to process.")


    print("\n--- Workout Complete ---")
    print(f"Total Reps Detected: {analyzer.rep_count}")
    print(f"Final logged feedback for the session: {analyzer.feedback_log}")

