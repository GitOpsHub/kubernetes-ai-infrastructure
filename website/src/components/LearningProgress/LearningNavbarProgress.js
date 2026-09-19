import React from 'react';
import { useLearningProgress } from '../../context/LearningProgressContext';

export default function LearningNavbarProgress() {
  const {
    progressPercent,
    completedCount,
    totalCount,
    openModal,
    mounted,
  } = useLearningProgress();

  const displayPercent = mounted ? progressPercent : 0;
  const displayCount = mounted ? completedCount : 0;

  return (
    <div className="learning-navbar-item-wrapper">
      <button
        type="button"
        className="learning-navbar-badge-btn"
        onClick={openModal}
        aria-label="View learning progress and curriculum syllabus"
        title={`Learning Progress: ${displayCount}/${totalCount} modules completed (${displayPercent}%). Click to open tracker.`}
      >
        <span className="learning-navbar-icon">🎓</span>
        <div className="learning-navbar-text-group">
          <span className="learning-navbar-label">
            <span className="learning-navbar-count">{displayCount}/{totalCount}</span>
            <span className="learning-navbar-percent">({displayPercent}%)</span>
          </span>
          <div className="learning-navbar-mini-track">
            <div
              className="learning-navbar-mini-fill"
              style={{ width: `${displayPercent}%` }}
            />
          </div>
        </div>
      </button>

      {/* Global overall course progress line under the navbar */}
      <div
        className="learning-navbar-global-bar"
        title={`Overall Learning Progress: ${displayPercent}%`}
      >
        <div
          className="learning-navbar-global-fill"
          style={{ width: `${displayPercent}%` }}
        />
      </div>
    </div>
  );
}
