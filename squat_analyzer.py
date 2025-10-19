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
        self.min_hip_y_in_rep = float('inf')

        # --- Frame Buffer for State Change ---
        self.FRAME_BUFFER = 3
        self.up_frames = 0
        self.down_frames = 0

        # --- Form Thresholds (Tunable) ---
        # Rep Counting
        self.rep_threshold_angle = 160  # Knee angle must be > this to be "up"

        # Depth Check
        self.depth_threshold_ratio = 1.0  # hip.y must be <= knee.y * this ratio

        # Knee Position Checks (relative to ankle distance)
        self.knee_caving_threshold_ratio = 0.8  # knee_dist < ankle_dist * this = Caving
        self.knee_splaying_threshold_ratio = 1.4 # knee_dist > ankle_dist * this = Splaying

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

            # Use average hip height for depth check
            avg_hip_y = (l_hip['y'] + r_hip['y']) / 2
            avg_knee_y = (l_knee['y'] + r_knee['y']) / 2
            
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
                # Reset the minimum hip height for the new rep
                self.min_hip_y_in_rep = avg_hip_y

            # While in the 'down' phase...
            elif self.stage == 'down':
                # Continuously track the lowest hip position
                self.min_hip_y_in_rep = min(self.min_hip_y_in_rep, avg_hip_y)

                # --- 1. Knee Caving / Splaying Check (performed during descent) ---
                knee_dist = abs(l_knee['x'] - r_knee['x'])
                ankle_dist = abs(l_ankle['x'] - r_ankle['x'])
                
                if ankle_dist > 0: # Avoid division by zero
                    knee_to_ankle_ratio = knee_dist / ankle_dist
                    
                    if knee_to_ankle_ratio < self.knee_caving_threshold_ratio:
                        feedback_this_frame.append("Push your knees out!")
                    elif knee_to_ankle_ratio > self.knee_splaying_threshold_ratio:
                        feedback_this_frame.append("Don't let your knees flare out too wide!")

                # A rep attempt ends when the user has been 'up' for enough frames
                if self.up_frames >= self.FRAME_BUFFER:
                    self.stage = 'up'
                    
                    # --- 2. Depth Check (performed at the end of the rep) ---
                    # Check if the lowest hip point was below the knee level
                    if self.min_hip_y_in_rep > (avg_knee_y * self.depth_threshold_ratio):
                        feedback_this_frame.append("Go deeper!")
                    else:
                        # Only count the rep if depth was good
                        self.rep_count += 1
                    
                    # Reset tracker for the next rep
                    self.min_hip_y_in_rep = float('inf')

            # Add new, unique feedback to the session log
            unique_feedback_in_log = set(self.feedback_log)
            for item in feedback_this_frame:
                if item not in unique_feedback_in_log:
                    self.feedback_log.append(item)
                    unique_feedback_in_log.add(item)
                    
            return feedback_this_frame

        except KeyError as e:
            return [f"Missing landmark: {e}"]
        except Exception as e:
            return [f"An error occurred during squat analysis: {e}"]

# --- Example Usage ---
if __name__ == '__main__':
    # This example simulates a few frames of data to test the logic
    # In a real scenario, you would load this from a file like in the pushup analyzer
    print("--- Running a simulated squat analysis ---")
    
    analyzer = SquatAnalyzer()

    # Create some dummy landmark data for testing
    up_pose = {'landmarks': {
        'left_hip': {'x': 0.4, 'y': 0.5, 'z': 0}, 'right_hip': {'x': 0.6, 'y': 0.5, 'z': 0},
        'left_knee': {'x': 0.4, 'y': 0.7, 'z': 0}, 'right_knee': {'x': 0.6, 'y': 0.7, 'z': 0},
        'left_ankle': {'x': 0.4, 'y': 0.9, 'z': 0}, 'right_ankle': {'x': 0.6, 'y': 0.9, 'z': 0}
    }, 'relative_time': 0}
    
    down_pose_good = {'landmarks': {
        'left_hip': {'x': 0.4, 'y': 0.7, 'z': 0}, 'right_hip': {'x': 0.6, 'y': 0.7, 'z': 0},
        'left_knee': {'x': 0.4, 'y': 0.7, 'z': 0}, 'right_knee': {'x': 0.6, 'y': 0.7, 'z': 0},
        'left_ankle': {'x': 0.4, 'y': 0.9, 'z': 0}, 'right_ankle': {'x': 0.6, 'y': 0.9, 'z': 0}
    }, 'relative_time': 1}

    down_pose_caving = {'landmarks': {
        'left_hip': {'x': 0.4, 'y': 0.6, 'z': 0}, 'right_hip': {'x': 0.6, 'y': 0.6, 'z': 0},
        'left_knee': {'x': 0.45, 'y': 0.7, 'z': 0}, 'right_knee': {'x': 0.55, 'y': 0.7, 'z': 0}, # Knees are closer
        'left_ankle': {'x': 0.4, 'y': 0.9, 'z': 0}, 'right_ankle': {'x': 0.6, 'y': 0.9, 'z': 0}
    }, 'relative_time': 2}
    
    # Simulate a sequence of frames for one rep
    workout_clip = [up_pose]*5 + [down_pose_caving]*5 + [down_pose_good]*5 + [up_pose]*5

    for i, frame in enumerate(workout_clip):
        feedback = analyzer.process_frame(frame)
        if feedback:
            print(f"Frame {i+1}: Feedback -> {feedback}")

    print("\n--- Workout Complete ---")
    print(f"Total Reps Detected: {analyzer.rep_count}")
    print(f"Final logged feedback for the session: {analyzer.feedback_log}")

