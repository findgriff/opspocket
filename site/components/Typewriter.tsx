'use client';

/**
 * Typewriter — prints [text] character-by-character, with a blinking caret
 * and an optional keystroke sound. Respects `prefers-reduced-motion` by
 * flipping to the completed string immediately.
 */

import { useEffect, useRef, useState } from 'react';
import { useReducedMotion } from 'framer-motion';
import { useSound } from './SoundManager';

type Props = {
  text: string;
  speed?: number;      // ms per character (default 40)
  startDelay?: number; // ms before the first character
  className?: string;
  sound?: boolean;     // play keystroke sound (default true)
  onDone?: () => void;
};

export default function Typewriter({
  text,
  speed = 40,
  startDelay = 0,
  className,
  sound = true,
  onDone,
}: Props) {
  const reduced = useReducedMotion();
  const { type } = useSound();
  const [shown, setShown] = useState(reduced ? text : '');
  const idxRef = useRef(0);

  useEffect(() => {
    if (reduced) {
      setShown(text);
      onDone?.();
      return;
    }
    idxRef.current = 0;
    setShown('');
    let cancelled = false;
    const start = setTimeout(() => {
      const step = () => {
        if (cancelled) return;
        idxRef.current += 1;
        setShown(text.slice(0, idxRef.current));
        if (sound && idxRef.current % 2 === 0) type();
        if (idxRef.current < text.length) {
          setTimeout(step, speed + Math.random() * 10 - 5);
        } else {
          onDone?.();
        }
      };
      step();
    }, startDelay);
    return () => {
      cancelled = true;
      clearTimeout(start);
    };
  }, [text, speed, startDelay, reduced, sound, type, onDone]);

  return <span className={`${className ?? ''} caret`}>{shown}</span>;
}
