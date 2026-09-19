import React, { createContext, useContext, useState, useEffect, useCallback, useMemo } from 'react';
import { CHAPTERS } from '../data/chapters';

const STORAGE_KEY = 'k8s_ai_completed_chapters';

const LearningProgressContext = createContext({
  completedChapters: [],
  isCompleted: () => false,
  toggleChapter: () => {},
  markChapter: () => {},
  resetProgress: () => {},
  markAllCompleted: () => {},
  progressPercent: 0,
  completedCount: 0,
  totalCount: CHAPTERS.length,
  isModalOpen: false,
  openModal: () => {},
  closeModal: () => {},
  toggleModal: () => {},
});

export function LearningProgressProvider({ children }) {
  const [completedChapters, setCompletedChapters] = useState([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [mounted, setMounted] = useState(false);

  // Load from localStorage after mount (SSR safe)
  useEffect(() => {
    setMounted(true);
    try {
      if (typeof window !== 'undefined' && window.localStorage) {
        const stored = window.localStorage.getItem(STORAGE_KEY);
        if (stored) {
          const parsed = JSON.parse(stored);
          if (Array.isArray(parsed)) {
            setCompletedChapters(parsed);
          }
        }
      }
    } catch (err) {
      console.warn('Could not load learning progress from localStorage', err);
    }
  }, []);

  // Save to localStorage whenever completedChapters changes (after mount)
  const saveToStorage = useCallback((items) => {
    try {
      if (typeof window !== 'undefined' && window.localStorage) {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
      }
    } catch (err) {
      console.warn('Could not save learning progress to localStorage', err);
    }
  }, []);

  const isCompleted = useCallback(
    (chapterId) => completedChapters.includes(chapterId),
    [completedChapters]
  );

  const toggleChapter = useCallback(
    (chapterId) => {
      setCompletedChapters((prev) => {
        let updated;
        if (prev.includes(chapterId)) {
          updated = prev.filter((id) => id !== chapterId);
        } else {
          updated = [...prev, chapterId];
        }
        saveToStorage(updated);
        return updated;
      });
    },
    [saveToStorage]
  );

  const markChapter = useCallback(
    (chapterId, status) => {
      setCompletedChapters((prev) => {
        const exists = prev.includes(chapterId);
        if (status && !exists) {
          const updated = [...prev, chapterId];
          saveToStorage(updated);
          return updated;
        } else if (!status && exists) {
          const updated = prev.filter((id) => id !== chapterId);
          saveToStorage(updated);
          return updated;
        }
        return prev;
      });
    },
    [saveToStorage]
  );

  const resetProgress = useCallback(() => {
    setCompletedChapters([]);
    saveToStorage([]);
  }, [saveToStorage]);

  const markAllCompleted = useCallback(() => {
    const allIds = CHAPTERS.map((c) => c.id);
    setCompletedChapters(allIds);
    saveToStorage(allIds);
  }, [saveToStorage]);

  const openModal = useCallback(() => setIsModalOpen(true), []);
  const closeModal = useCallback(() => setIsModalOpen(false), []);
  const toggleModal = useCallback(() => setIsModalOpen((v) => !v), []);

  const totalCount = CHAPTERS.length;
  const completedCount = completedChapters.length;
  const progressPercent = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const value = useMemo(
    () => ({
      completedChapters,
      isCompleted,
      toggleChapter,
      markChapter,
      resetProgress,
      markAllCompleted,
      progressPercent,
      completedCount,
      totalCount,
      isModalOpen,
      openModal,
      closeModal,
      toggleModal,
      mounted,
    }),
    [
      completedChapters,
      isCompleted,
      toggleChapter,
      markChapter,
      resetProgress,
      markAllCompleted,
      progressPercent,
      completedCount,
      totalCount,
      isModalOpen,
      openModal,
      closeModal,
      toggleModal,
      mounted,
    ]
  );

  return (
    <LearningProgressContext.Provider value={value}>
      {children}
    </LearningProgressContext.Provider>
  );
}

export function useLearningProgress() {
  const context = useContext(LearningProgressContext);
  if (!context) {
    throw new Error('useLearningProgress must be used within a LearningProgressProvider');
  }
  return context;
}

export default LearningProgressContext;
