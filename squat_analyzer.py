import json
from exercise_analyzer import ExerciseAnalyzer

class SquatAnalyzer(ExerciseAnalyzer):
    """
    Analyzes a stream of pose landmarks to provide feedback on squat form.
    Checks for depth, knee caving (valgus), and knee splaying (varus).
    """
    def __init__(self):
        super().__init__()
        # --- Squat Specific State Tracking ---
        self.stage = "up"
        # FIX: Track the MAXIMUM y-value (lowest point) reached by the hip in a rep.
        # Renamed for clarity. Initialized to 0 as coordinates are typically 0-1.
        self.max_hip_y_in_rep = 0.0

        # --- Frame Buffer for State Change ---
        self.FRAME_BUFFER = 3
        self.up_frames = 0
        self.down_frames = 0

        # --- Form Thresholds (Tunable) ---
        # Rep Counting
        self.rep_threshold_angle = 170  # Knee angle must be > this to be "up"

        # Knee Position Checks (relative to ankle distance)
        self.knee_feedback_given_in_rep = False
        self.knee_caving_threshold_ratio = 0.8  # knee_dist < ankle_dist * this = Caving
        self.knee_splaying_threshold_ratio = 1.6 # knee_dist > ankle_dist * this = Splaying

    def process_frame(self, frame_data):
        """
        Processes a single frame of landmark data for squat analysis.
        """
        self.frame_count += 1
        landmarks = frame_data['landmarks']
        feedback_this_frame = []

        try:
            # --- Get key landmarks for both sides ---
            l_hip = self.get_landmark(landmarks, 'left_hip')
            l_knee = self.get_landmark(landmarks, 'left_knee')
            l_ankle = self.get_landmark(landmarks, 'left_ankle')
            
            r_hip = self.get_landmark(landmarks, 'right_hip')
            r_knee = self.get_landmark(landmarks, 'right_knee')
            r_ankle = self.get_landmark(landmarks, 'right_ankle')

            # --- Calculate angles and distances ---
            # Use the average of both knees for rep counting state
            left_knee_angle = self.calculate_angle(l_hip, l_knee, l_ankle)
            right_knee_angle = self.calculate_angle(r_hip, r_knee, r_ankle)
            avg_knee_angle = (left_knee_angle + right_knee_angle) / 2

            # Use average hip and knee height for depth check
            avg_hip_y = (l_hip[1] + r_hip[1]) / 2
            avg_knee_y = (l_knee[1] + r_knee[1]) / 2
            
            # --- Rep Counting and State Logic with Frame Buffer ---
            if avg_knee_angle > self.rep_threshold_angle:
                self.up_frames += 1
                self.down_frames = 0
            else:
                self.down_frames += 1
                self.up_frames = 0

            # A rep begins when the user has been 'down' for enough frames
            if self.stage == 'up' and self.down_frames >= self.FRAME_BUFFER:
                self.stage = 'down'
                # FIX: Reset the maximum hip height tracker for the new rep.
                self.max_hip_y_in_rep = avg_hip_y
                self.knee_feedback_given_in_rep = False

            # While in the 'down' phase...
            elif self.stage == 'down':
                # FIX: Continuously track the lowest hip position (maximum y-value).
                self.max_hip_y_in_rep = max(self.max_hip_y_in_rep, avg_hip_y)

                # --- 1. Knee Caving / Splaying Check (performed during descent) ---
                knee_dist = abs(l_knee[0] - r_knee[0])
                ankle_dist = abs(l_ankle[0] - r_ankle[0])
                
                if ankle_dist > 0: # Avoid division by zero
                    knee_to_ankle_ratio = knee_dist / ankle_dist
                    
                    if not self.knee_feedback_given_in_rep:
                        if knee_to_ankle_ratio < self.knee_caving_threshold_ratio:
                            feedback_this_frame.append("Push your knees out!")
                            self.knee_feedback_given_in_rep = True
                        elif knee_to_ankle_ratio > self.knee_splaying_threshold_ratio:
                            feedback_this_frame.append("Don't let your knees flare out too wide!")
                            self.knee_feedback_given_in_rep = True

                # A rep attempt ends when the user has been 'up' for enough frames
                if self.up_frames >= self.FRAME_BUFFER:
                    self.stage = 'up'
                    
                    # --- 2. Depth Check (performed at the end of the rep) ---
                    # FIX: Check if the lowest hip point (max y) went below the knee level (avg_knee_y).
                    if self.max_hip_y_in_rep < avg_knee_y:
                        feedback_this_frame.append("Go deeper!")
                    else:
                        # Only count the rep if depth was good
                        self.rep_count += 1
                    
                    # Reset tracker for the next rep
                    self.max_hip_y_in_rep = 0.0

            # Add new, unique feedback to the session log
            unique_feedback_in_log = set(self.feedback_log)
            for item in feedback_this_frame:
                if item not in unique_feedback_in_log:
                    self.feedback_log.append(item)
                    unique_feedback_in_log.add(item)
                    
            return feedback_this_frame

        except KeyError as e:
            return [{e}]
        except Exception as e:
            return [f"An error occurred during squat analysis: {e}"]

if __name__ == '__main__':
    json_file_path = 'goodsquat_training_data.json'
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
    analyzer = SquatAnalyzer()
    
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

