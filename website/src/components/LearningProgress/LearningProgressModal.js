import React, { useEffect } from 'react';
import Link from '@docusaurus/Link';
import { useLearningProgress } from '../../context/LearningProgressContext';
import { CHAPTERS, CATEGORIES } from '../../data/chapters';

function getMilestoneText(percent) {
  if (percent === 0) return { title: 'Start Your Journey', desc: 'Complete chapters to master Kubernetes AI infrastructure.', icon: '🎯' };
  if (percent < 30) return { title: 'Foundations Underway', desc: 'Grasping GPUs, scheduling, and driver operators.', icon: '🏗️' };
  if (percent < 60) return { title: 'Scaling Workloads', desc: 'Queueing batch jobs, distributed training, and Ray clusters.', icon: '🧠' };
  if (percent < 90) return { title: 'Advanced Platform Engineer', desc: 'vLLM inference, autoscaling, security, and GitOps.', icon: '🚀' };
  if (percent < 100) return { title: 'Capstone Ready', desc: 'Almost there! Finish the final operational modules.', icon: '⚡' };
  return { title: 'AI Infrastructure Architect!', desc: 'Congratulations! You mastered Kubernetes for AI workloads.', icon: '🏆' };
}

export default function LearningProgressModal() {
  const {
    isModalOpen,
    closeModal,
    completedChapters,
    isCompleted,
    toggleChapter,
    resetProgress,
    markAllCompleted,
    progressPercent,
    completedCount,
    totalCount,
    mounted,
  } = useLearningProgress();

  useEffect(() => {
    if (!isModalOpen) return;

    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        closeModal();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    // Prevent body scroll when modal is open
    document.body.style.overflow = 'hidden';

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'unset';
    };
  }, [isModalOpen, closeModal]);

  if (!isModalOpen) return null;

  const milestone = getMilestoneText(progressPercent);

  return (
    <div className="learning-modal-overlay" onClick={closeModal}>
      <div
        className="learning-modal-container"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="learning-modal-title"
      >
        {/* Header */}
        <div className="learning-modal-header">
          <div className="learning-modal-header-text">
            <h2 id="learning-modal-title" className="learning-modal-title">
              <span className="learning-modal-title-icon">🎓</span> Learning Progress Tracker
            </h2>
            <p className="learning-modal-subtitle">
              Track your course completion across all 20 hands-on modules.
            </p>
          </div>
          <button
            className="learning-modal-close-btn"
            onClick={closeModal}
            aria-label="Close modal"
          >
            ✕
          </button>
        </div>

        {/* Milestone & Stats Banner */}
        <div className="learning-stats-card">
          <div className="learning-stats-top">
            <div className="learning-stats-milestone">
              <span className="learning-milestone-icon">{milestone.icon}</span>
              <div>
                <div className="learning-milestone-title">{milestone.title}</div>
                <div className="learning-milestone-desc">{milestone.desc}</div>
              </div>
            </div>
            <div className="learning-stats-badge">
              <span className="learning-stats-percent">{mounted ? progressPercent : 0}%</span>
              <span className="learning-stats-count">
                {mounted ? completedCount : 0} of {totalCount} done
              </span>
            </div>
          </div>

          {/* Progress bar */}
          <div className="learning-modal-progress-track">
            <div
              className="learning-modal-progress-fill"
              style={{ width: `${mounted ? progressPercent : 0}%` }}
            />
          </div>

          {/* Quick Actions */}
          <div className="learning-stats-actions">
            <button
              type="button"
              className="learning-action-btn"
              onClick={() => {
                if (window.confirm('Mark all 20 chapters as completed?')) {
                  markAllCompleted();
                }
              }}
            >
              ✓ Mark All Complete
            </button>
            <button
              type="button"
              className="learning-action-btn learning-action-btn--secondary"
              onClick={() => {
                if (window.confirm('Are you sure you want to reset your learning progress to 0%?')) {
                  resetProgress();
                }
              }}
            >
              ↺ Reset Progress
            </button>
          </div>
        </div>

        {/* Syllabus / Chapters by Category */}
        <div className="learning-modal-syllabus">
          <h3 className="learning-syllabus-heading">Course Modules</h3>
          {CATEGORIES.map((cat) => {
            const catChapters = CHAPTERS.filter((ch) => cat.chapterIds.includes(ch.id));
            const catCompleted = catChapters.filter((ch) => isCompleted(ch.id)).length;
            const catTotal = catChapters.length;

            return (
              <div key={cat.name} className="learning-category-group">
                <div className="learning-category-header">
                  <div className="learning-category-title">
                    <span className="learning-category-icon">{cat.icon}</span>
                    <span>{cat.name}</span>
                  </div>
                  <span className="learning-category-count">
                    {catCompleted}/{catTotal} completed
                  </span>
                </div>

                <div className="learning-chapters-list">
                  {catChapters.map((ch) => {
                    const done = isCompleted(ch.id);
                    return (
                      <div
                        key={ch.id}
                        className={`learning-chapter-row ${done ? 'learning-chapter-row--done' : ''}`}
                      >
                        <label className="learning-checkbox-container">
                          <input
                            type="checkbox"
                            checked={done}
                            onChange={() => toggleChapter(ch.id)}
                            className="learning-checkbox-input"
                          />
                          <span className="learning-custom-checkbox">
                            {done && '✓'}
                          </span>
                        </label>

                        <div className="learning-chapter-info">
                          <span className="learning-chapter-num">Ch {ch.number}</span>
                          <Link
                            to={ch.route}
                            onClick={closeModal}
                            className="learning-chapter-link"
                          >
                            {ch.title}
                          </Link>
                          <p className="learning-chapter-desc">{ch.description}</p>
                        </div>

                        {done ? (
                          <span className="learning-status-pill learning-status-pill--completed">
                            Done
                          </span>
                        ) : (
                          <Link
                            to={ch.route}
                            onClick={closeModal}
                            className="learning-status-pill learning-status-pill--goto"
                          >
                            Start →
                          </Link>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>

        {/* Footer */}
        <div className="learning-modal-footer">
          <span className="learning-modal-footer-note">
            💡 Progress is automatically saved locally in your browser.
          </span>
          <button
            type="button"
            className="learning-modal-done-btn"
            onClick={closeModal}
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
