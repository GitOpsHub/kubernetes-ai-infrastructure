import React, { useState, useEffect } from 'react';

export default function ReadingProgressBar() {
  const [scrollProgress, setScrollProgress] = useState(0);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    let animationFrameId = null;

    const handleScroll = () => {
      if (animationFrameId) return;

      animationFrameId = requestAnimationFrame(() => {
        const totalHeight = document.documentElement.scrollHeight - window.innerHeight;
        if (totalHeight > 100) {
          const progress = Math.min(100, Math.max(0, (window.scrollY / totalHeight) * 100));
          setScrollProgress(progress);
          setIsVisible(true);
        } else {
          setIsVisible(false);
        }
        animationFrameId = null;
      });
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('resize', handleScroll, { passive: true });
    handleScroll();

    return () => {
      window.removeEventListener('scroll', handleScroll);
      window.removeEventListener('resize', handleScroll);
      if (animationFrameId) {
        cancelAnimationFrame(animationFrameId);
      }
    };
  }, []);

  if (!isVisible) return null;

  return (
    <div
      className="reading-progress-track"
      aria-hidden="true"
      title={`Scroll progress: ${Math.round(scrollProgress)}%`}
    >
      <div
        className="reading-progress-bar"
        style={{ width: `${scrollProgress}%` }}
      />
    </div>
  );
}
