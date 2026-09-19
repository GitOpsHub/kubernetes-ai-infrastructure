import React from 'react';
import { LearningProgressProvider } from '@site/src/context/LearningProgressContext';
import ReadingProgressBar from '@site/src/components/LearningProgress/ReadingProgressBar';
import LearningProgressModal from '@site/src/components/LearningProgress/LearningProgressModal';

export default function Root({ children }) {
  return (
    <LearningProgressProvider>
      <ReadingProgressBar />
      {children}
      <LearningProgressModal />
    </LearningProgressProvider>
  );
}
