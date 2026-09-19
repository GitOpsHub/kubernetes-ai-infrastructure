import React from 'react';
import Footer from '@theme-original/DocItem/Footer';
import ChapterCompletionCard from '@site/src/components/LearningProgress/ChapterCompletionCard';

export default function FooterWrapper(props) {
  return (
    <>
      <ChapterCompletionCard />
      <Footer {...props} />
    </>
  );
}
