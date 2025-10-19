import cv2
import mediapipe as mp
import json
import time
from datetime import datetime
import numpy as np
import sys

class PostureDataCollector:
    def __init__(self, exercise_type, output_file="posture_data.json", video_file="posture_video.mp4"):
        # Initialize MediaPipe Pose
        self.mp_pose = mp.solutions.pose
        self.mp_drawing = mp.solutions.drawing_utils
        self.pose = self.mp_pose.Pose(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )
        
        self.exercise_type = exercise_type.lower()
        self.output_file = output_file
        self.video_file = video_file
        self.data_collection = []
        self.start_time = time.time()
        self.video_writer = None
        
        # Exercise-specific state
        self.pushup_count = 0
        self.pushup_state = "up"  # "up" or "down"
        self.stretch_hold_start = None
        self.stretch_detected = False
        self.recording_started = False
        
        # Key landmarks for posture/back analysis
        self.key_landmarks = {
            'nose': 0,
            'left_shoulder': 11,
            'right_shoulder': 12,
            'left_elbow': 13,
            'right_elbow': 14,
            'left_wrist': 15,
            'right_wrist': 16,
            'left_hip': 23,
            'right_hip': 24,
            'left_knee': 25,
            'right_knee': 26,
            'left_ankle': 27,
            'right_ankle': 28
        }
    
    def calculate_angle(self, point1, point2, point3):
        """Calculate angle between three points"""
        a = np.array([point1.x, point1.y])
        b = np.array([point2.x, point2.y])
        c = np.array([point3.x, point3.y])
        
        radians = np.arctan2(c[1] - b[1], c[0] - b[0]) - np.arctan2(a[1] - b[1], a[0] - b[0])
        angle = np.abs(radians * 180.0 / np.pi)
        
        if angle > 180.0:
            angle = 360 - angle
        
        return angle
    
    def detect_pushup_position(self, landmarks):
        """Detect if person is in up or down position for pushup"""
        # Get elbow angle
        left_elbow_angle = self.calculate_angle(
            landmarks[self.key_landmarks['left_shoulder']],
            landmarks[self.key_landmarks['left_elbow']],
            landmarks[self.key_landmarks['left_wrist']]
        )
        
        right_elbow_angle = self.calculate_angle(
            landmarks[self.key_landmarks['right_shoulder']],
            landmarks[self.key_landmarks['right_elbow']],
            landmarks[self.key_landmarks['right_wrist']]
        )
        
        avg_elbow_angle = (left_elbow_angle + right_elbow_angle) / 2
        
        # Down position: elbows bent (angle < 90)
        # Up position: elbows straight (angle > 160)
        if avg_elbow_angle > 160:
            return "up"
        elif avg_elbow_angle < 90:
            return "down"
        else:
            return self.pushup_state  # Keep current state if in transition
    
    def detect_hip_flexor_stretch(self, landmarks):
        """Detect if person is in half-kneeling hip-flexor stretch position"""
        # Check knee angles to detect kneeling position
        left_knee_angle = self.calculate_angle(
            landmarks[self.key_landmarks['left_hip']],
            landmarks[self.key_landmarks['left_knee']],
            landmarks[self.key_landmarks['left_ankle']]
        )
        
        right_knee_angle = self.calculate_angle(
            landmarks[self.key_landmarks['right_hip']],
            landmarks[self.key_landmarks['right_knee']],
            landmarks[self.key_landmarks['right_ankle']]
        )
        
        # Half-kneeling: one knee bent (70-110°), one leg forward (angle > 130°)
        # Only checking knee angles, no hip/elbow requirements
        one_knee_bent = (70 <= left_knee_angle <= 110 and right_knee_angle > 130) or \
                        (70 <= right_knee_angle <= 110 and left_knee_angle > 130)
        
        return one_knee_bent
    
    def extract_landmark_data(self, landmarks, frame_timestamp):
        """Extract relevant landmark coordinates"""
        frame_data = {
            'timestamp': frame_timestamp,
            'relative_time': time.time() - self.start_time,
            'landmarks': {}
        }
        
        for name, idx in self.key_landmarks.items():
            landmark = landmarks[idx]
            frame_data['landmarks'][name] = {
                'x': landmark.x,
                'y': landmark.y,
                'z': landmark.z,
                'visibility': landmark.visibility
            }
        
        # Calculate additional features useful for posture analysis
        frame_data['calculated_features'] = self.calculate_features(landmarks)
        
        # Add exercise-specific data
        if self.exercise_type == "pushup":
            frame_data['pushup_count'] = self.pushup_count
            frame_data['pushup_state'] = self.pushup_state
        elif self.exercise_type == "stretch":
            frame_data['stretch_detected'] = self.stretch_detected
            if self.stretch_hold_start:
                frame_data['hold_duration'] = time.time() - self.stretch_hold_start
        
        return frame_data
    
    def calculate_features(self, landmarks):
        """Calculate useful features for posture analysis"""
        features = {}
        
        # Shoulder alignment
        left_shoulder = landmarks[11]
        right_shoulder = landmarks[12]
        features['shoulder_slope'] = (right_shoulder.y - left_shoulder.y) / (right_shoulder.x - left_shoulder.x + 1e-6)
        
        # Hip alignment
        left_hip = landmarks[23]
        right_hip = landmarks[24]
        features['hip_slope'] = (right_hip.y - left_hip.y) / (right_hip.x - left_hip.x + 1e-6)
        
        # Vertical alignment (shoulder to hip distance)
        shoulder_center_y = (left_shoulder.y + right_shoulder.y) / 2
        hip_center_y = (left_hip.y + right_hip.y) / 2
        features['torso_length'] = abs(hip_center_y - shoulder_center_y)
        
        # Forward lean (using nose and hip positions)
        nose = landmarks[0]
        hip_center_x = (left_hip.x + right_hip.x) / 2
        features['forward_lean'] = nose.x - hip_center_x
        
        return features
    
    def save_data(self):
        """Save collected data to JSON file"""
        output = {
            'metadata': {
                'exercise_type': self.exercise_type,
                'total_frames': len(self.data_collection),
                'duration_seconds': time.time() - self.start_time,
                'collection_date': datetime.now().isoformat(),
                'key_landmarks': list(self.key_landmarks.keys())
            },
            'frames': self.data_collection
        }
        
        if self.exercise_type == "pushup":
            output['metadata']['total_pushups'] = self.pushup_count
        
        with open(self.output_file, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"\nData saved to {self.output_file}")
        print(f"Total frames captured: {len(self.data_collection)}")
    
    def run_pushup_mode(self, video_source=0, countdown_seconds=3, recording_duration=10):
        """Record pushups for a fixed duration"""
        cap = cv2.VideoCapture(video_source)
        
        if not cap.isOpened():
            print("Error: Could not open video source")
            return
        
        # Get video properties
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = int(cap.get(cv2.CAP_PROP_FPS))
        if fps == 0:
            fps = 30
        
        # Initialize video writer
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        self.video_writer = cv2.VideoWriter(self.video_file, fourcc, fps, (frame_width, frame_height))
        
        print(f"Push-up mode: Do as many push-ups as you can in {recording_duration} seconds")
        print(f"Starting in {countdown_seconds} seconds...")
        
        # Countdown phase
        countdown_start = time.time()
        while time.time() - countdown_start < countdown_seconds:
            success, frame = cap.read()
            if not success:
                break
            
            remaining = int(countdown_seconds - (time.time() - countdown_start)) + 1
            cv2.putText(frame, f"Starting in: {remaining}", (frame_width//2 - 150, frame_height//2), 
                       cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 255), 3)
            
            cv2.imshow('Push-up Tracker', frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                cap.release()
                cv2.destroyAllWindows()
                self.pose.close()
                return
        
        # Recording phase - record for fixed duration
        print(f"Recording for {recording_duration} seconds...")
        self.start_time = time.time()
        recording_start = time.time()
        frame_count = 0
        
        while time.time() - recording_start < recording_duration:
            success, frame = cap.read()
            if not success:
                break
            
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = self.pose.process(rgb_frame)
            
            if results.pose_landmarks:
                landmarks = results.pose_landmarks.landmark
                
                # Draw pose
                self.mp_drawing.draw_landmarks(
                    frame, results.pose_landmarks, self.mp_pose.POSE_CONNECTIONS,
                    self.mp_drawing.DrawingSpec(color=(245, 117, 66), thickness=2, circle_radius=2),
                    self.mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2, circle_radius=2)
                )
                
                # Detect pushup position (for data collection only)
                current_position = self.detect_pushup_position(landmarks)
                self.pushup_state = current_position
                
                # Extract and store data
                timestamp = datetime.now().isoformat()
                frame_data = self.extract_landmark_data(landmarks, timestamp)
                self.data_collection.append(frame_data)
                frame_count += 1
            
            # Calculate remaining time
            elapsed = time.time() - recording_start
            remaining = recording_duration - elapsed
            
            # Draw counter box
            box_height = 80
            cv2.rectangle(frame, (10, 10), (300, box_height), (0, 0, 0), -1)
            cv2.rectangle(frame, (10, 10), (300, box_height), (255, 255, 255), 2)
            
            cv2.putText(frame, "RECORDING", (20, 40), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
            cv2.putText(frame, f"Time left: {remaining:.1f}s", (20, 70), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 0), 2)
            
            self.video_writer.write(frame)
            cv2.imshow('Push-up Tracker', frame)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        
        print(f"Recording complete!")
        self.cleanup(cap)
    
    def run_stretch_mode(self, video_source=0, countdown_seconds=2, hold_detection_time=2, hold_duration=10):
        """Record stretch: starts after holding pose for 2 seconds, records for 10 seconds"""
        cap = cv2.VideoCapture(video_source)
        
        if not cap.isOpened():
            print("Error: Could not open video source")
            return
        
        # Get video properties
        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = int(cap.get(cv2.CAP_PROP_FPS))
        if fps == 0:
            fps = 30
        
        # Initialize video writer
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        self.video_writer = cv2.VideoWriter(self.video_file, fourcc, fps, (frame_width, frame_height))
        
        print(f"Hip-flexor stretch mode")
        print(f"Get into position. Recording starts after holding for {hold_detection_time} seconds")
        print(f"Starting in {countdown_seconds} seconds...")
        
        # Countdown phase
        countdown_start = time.time()
        while time.time() - countdown_start < countdown_seconds:
            success, frame = cap.read()
            if not success:
                break
            
            remaining = int(countdown_seconds - (time.time() - countdown_start)) + 1
            cv2.putText(frame, f"Starting in: {remaining}", (frame_width//2 - 150, frame_height//2), 
                       cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 255), 3)
            
            cv2.imshow('Stretch Tracker', frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                cap.release()
                cv2.destroyAllWindows()
                self.pose.close()
                return
        
        # Detection phase - wait for stretch to be held for required time
        print("Get into stretch position...")
        detection_complete = False
        
        while not detection_complete:
            success, frame = cap.read()
            if not success:
                break
            
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = self.pose.process(rgb_frame)
            
            if results.pose_landmarks:
                landmarks = results.pose_landmarks.landmark
                self.mp_drawing.draw_landmarks(
                    frame, results.pose_landmarks, self.mp_pose.POSE_CONNECTIONS,
                    self.mp_drawing.DrawingSpec(color=(245, 117, 66), thickness=2, circle_radius=2),
                    self.mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2, circle_radius=2)
                )
                
                # Check if in stretch position
                in_stretch = self.detect_hip_flexor_stretch(landmarks)
                
                if in_stretch:
                    if self.stretch_hold_start is None:
                        self.stretch_hold_start = time.time()
                    
                    hold_time = time.time() - self.stretch_hold_start
                    
                    if hold_time >= hold_detection_time:
                        detection_complete = True
                        self.stretch_detected = True
                        print("Stretch detected! Starting recording...")
                    else:
                        cv2.putText(frame, f"Hold position: {hold_time:.1f}s / {hold_detection_time}s", 
                                   (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)
                else:
                    self.stretch_hold_start = None
                    cv2.putText(frame, "Get into half-kneeling hip-flexor stretch", 
                               (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
            
            cv2.imshow('Stretch Tracker', frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                self.cleanup(cap)
                return
        
        # Recording phase - record for specified duration
        print(f"Recording for {hold_duration} seconds...")
        self.start_time = time.time()
        recording_start = time.time()
        frame_count = 0
        
        while time.time() - recording_start < hold_duration:
            success, frame = cap.read()
            if not success:
                break
            
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = self.pose.process(rgb_frame)
            
            if results.pose_landmarks:
                landmarks = results.pose_landmarks.landmark
                self.mp_drawing.draw_landmarks(
                    frame, results.pose_landmarks, self.mp_pose.POSE_CONNECTIONS,
                    self.mp_drawing.DrawingSpec(color=(245, 117, 66), thickness=2, circle_radius=2),
                    self.mp_drawing.DrawingSpec(color=(245, 66, 230), thickness=2, circle_radius=2)
                )
                
                timestamp = datetime.now().isoformat()
                frame_data = self.extract_landmark_data(landmarks, timestamp)
                self.data_collection.append(frame_data)
                frame_count += 1
            
            elapsed = time.time() - recording_start
            remaining = hold_duration - elapsed
            
            # Draw info box
            cv2.rectangle(frame, (10, 10), (300, 100), (0, 0, 0), -1)
            cv2.rectangle(frame, (10, 10), (300, 100), (255, 255, 255), 2)
            
            cv2.putText(frame, "RECORDING", (20, 40), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
            cv2.putText(frame, f"Time left: {remaining:.1f}s", (20, 75), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            
            self.video_writer.write(frame)
            cv2.imshow('Stretch Tracker', frame)
            
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        
        print("Recording complete!")
        self.cleanup(cap)
    
    def cleanup(self, cap):
        """Release resources and save data"""
        if self.video_writer:
            self.video_writer.release()
        cap.release()
        cv2.destroyAllWindows()
        self.pose.close()
        
        if self.data_collection:
            self.save_data()
            print(f"Video saved to {self.video_file}")
        else:
            print("No data collected")
    
    def run(self, video_source=0):
        """Main run method that routes to appropriate exercise mode"""
        if self.exercise_type == "pushup":
            self.run_pushup_mode(video_source=video_source, countdown_seconds=3, recording_duration=10)
        elif self.exercise_type == "stretch":
            self.run_stretch_mode(video_source=video_source, countdown_seconds=2, 
                                 hold_detection_time=2, hold_duration=10)
        else:
            print(f"Unknown exercise type: {self.exercise_type}")
            print("Supported types: 'pushup', 'stretch'")


if __name__ == "__main__":
    # Get exercise type from command line argument
    if len(sys.argv) < 2:
        print("Usage: python script.py <exercise_type>")
        print("Exercise types: pushup, stretch")
        sys.exit(1)
    
    exercise = sys.argv[1]
    
    # Create collector instance
    collector = PostureDataCollector(
        exercise_type=exercise,
        output_file=f"{exercise}_training_data.json",
        video_file=f"{exercise}_recording.mp4"
    )
    
    # Run with webcam
    collector.run(video_source=1)