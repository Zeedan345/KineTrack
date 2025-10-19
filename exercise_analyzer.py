import numpy as np
from abc import ABC, abstractmethod

class ExerciseAnalyzer(ABC):
    """
    Abstract base class for analyzing an exercise from pose landmark data.
    """
    def __init__(self):
        """Initializes common state for all exercise analyzers."""
        self.rep_count = 0
        self.stage = None # Varies by exercise, e.g., 'up'/'down', 'left'/'right'
        self.feedback_log = []
        self.frame_count = 0

    @abstractmethod
    def process_frame(self, frame_data):
        """
        Processes a single frame of landmark data to analyze form and count reps.
        This method must be implemented by any subclass.

        Args:
            frame_data (dict): A dictionary containing timestamp and landmark data.

        Returns:
            list: A list of feedback strings generated for the current frame.
        """
        pass

    def get_landmark(self, landmarks, name):
        """Utility to extract 2D (x, y) coordinates from landmark data."""
        try:
            return [landmarks[name]['x'], landmarks[name]['y']]
        except KeyError:
            # Raise a more informative error
            raise KeyError(f"Landmark '{name}' not found in the provided data.")

    def calculate_angle(self, a, b, c):
        """
        Calculates the angle at point b for three 2D points (a, b, c).
        Points should be provided as lists or tuples of [x, y].
        """
        a = np.array(a) # First point
        b = np.array(b) # Midpoint (vertex of the angle)
        c = np.array(c) # End point
        
        radians = np.arctan2(c[1]-b[1], c[0]-b[0]) - np.arctan2(a[1]-b[1], a[0]-b[0])
        angle = np.abs(radians*180.0/np.pi)
        
        if angle > 180.0:
            angle = 360 - angle
            
        return angle
