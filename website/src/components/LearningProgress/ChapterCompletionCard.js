import React, { useState } from 'react';
import { useLocation } from '@docusaurus/router';
import Link from '@docusaurus/Link';
import { useLearningProgress } from '../../context/LearningProgressContext';
import { CHAPTERS, getChapterByPath, getNextChapter } from '../../data/chapters';

export default function ChapterCompletionCard() {
  const location = useLocation();
  const {
    isCompleted,
    toggleChapter,
    progressPercent,
    completedCount,
    totalCount,
    openModal,
    mounted,
  } = useLearningProgress();

  const [justCompleted, setJustCompleted] = useState(false);

  // Match current path to chapter
  const currentChapter = getChapterByPath(location.pathname);
  const nextChapter = currentChapter ? getNextChapter(currentChapter.id) : null;
  const isCurrentDone = currentChapter && isCompleted(currentChapter.id);

  const handleToggle = () => {
    if (!currentChapter) return;
    const nextStatus = !isCurrentDone;
    toggleChapter(currentChapter.id);
    if (nextStatus) {
      setJustCompleted(true);
      setTimeout(() => setJustCompleted(false), 3500);
    }
  };

  const displayPercent = mounted ? progressPercent : 0;
  const displayCount = mounted ? completedCount : 0;

  return (
    <div className={`learning-doc-card ${isCurrentDone ? 'learning-doc-card--completed' : ''} ${justCompleted ? 'learning-doc-card--celebrate' : ''}`}>
      {/* Top Banner / Status */}
      <div className="learning-doc-card-header">
        <div className="learning-doc-card-title-group">
          <span className="learning-doc-card-badge">
            {currentChapter ? `Chapter ${currentChapter.number}` : 'Course Progress'}
          </span>
          <h3 className="learning-doc-card-heading">
            {currentChapter ? currentChapter.title : 'Kubernetes AI Infrastructure'}
          </h3>
        </div>

        {currentChapter && (
          <button
            type="button"
            onClick={handleToggle}
            className={`learning-complete-btn ${isCurrentDone ? 'learning-complete-btn--done' : 'learning-complete-btn--todo'}`}
            aria-pressed={isCurrentDone}
          >
            {isCurrentDone ? (
              <>
                <span className="learning-btn-icon">✓</span>
                <span>Completed!</span>
              </>
            ) : (
              <>
                <span className="learning-btn-icon">○</span>
                <span>Mark as Complete</span>
              </>
            )}
          </button>
        )}
      </div>

      {justCompleted && (
        <div className="learning-celebration-banner">
          ✨ Great work completing Chapter {currentChapter?.number}! Keep up the momentum.
        </div>
      )}

      {/* Progress Bar Group */}
      <div className="learning-doc-progress-section">
        <div className="learning-doc-progress-meta">
          <span className="learning-doc-progress-label">
            Course Completion Progress:
          </span>
          <span className="learning-doc-progress-stats">
            <strong>{displayCount}</strong> of <strong>{totalCount}</strong> chapters completed ({displayPercent}%)
          </span>
        </div>
        <div className="learning-doc-progress-track">
          <div
            className="learning-doc-progress-fill"
            style={{ width: `${displayPercent}%` }}
          />
        </div>
      </div>

      {/* Action Links */}
      <div className="learning-doc-card-footer">
        <button
          type="button"
          className="learning-card-btn-link"
          onClick={openModal}
        >
          📋 View Full Syllabus & Tracker
        </button>

        {nextChapter ? (
          <Link
            to={nextChapter.route}
            className="learning-next-chapter-btn"
          >
            Next: Ch {nextChapter.number} · {nextChapter.title} →
          </Link>
        ) : currentChapter ? (
          <span className="learning-capstone-complete-badge">
            🏆 You are at the final chapter of the course!
          </span>
        ) : (
          <Link
            to="/prerequisites"
            className="learning-next-chapter-btn"
          >
            Start Chapter 00: Prerequisites →
          </Link>
        )}
      </div>
    </div>
  );
}
