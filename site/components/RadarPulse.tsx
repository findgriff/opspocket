'use client';

/**
 * RadarPulse — a continuous, gentle "sonar ping" emanating from a point.
 * Used in the hero and the /cloud page to give the site a living, monitoring
 * feel without being distracting. Three concentric rings scale + fade in
 * staggered phase so there's always one on screen.
 */

import { motion, useReducedMotion } from 'framer-motion';
import { useEffect } from 'react';
import { useSound } from './SoundManager';

type Props = {
  size?: number;        // base size of the innermost ring in px
  color?: string;       // CSS colour, default red
  className?: string;
  sound?: boolean;      // fire a radar tick every cycle (default false)
};

export default function RadarPulse({
  size = 32,
  color = 'var(--color-red)',
  className,
  sound = false,
}: Props) {
  const reduced = useReducedMotion();
  const { radar, armed } = useSound();

  // Optional low-frequency radar tick — every ~4.5s.
  useEffect(() => {
    if (!sound || reduced || !armed) return;
    const id = setInterval(() => radar(), 4500);
    return () => clearInterval(id);
  }, [sound, reduced, armed, radar]);

  if (reduced) {
    return (
      <span
        className={className}
        style={{
          width: size,
          height: size,
          borderRadius: '50%',
          background: color,
          display: 'inline-block',
        }}
      />
    );
  }

  const rings = [0, 0.9, 1.8];
  return (
    <span className={`relative inline-block ${className ?? ''}`} style={{ width: size, height: size }}>
      {/* Solid centre */}
      <span
        className="absolute inset-0 rounded-full"
        style={{
          background: color,
          boxShadow: `0 0 16px ${color}, 0 0 32px ${color}`,
        }}
      />
      {/* Three outbound rings */}
      {rings.map((delay, i) => (
        <motion.span
          key={i}
          className="absolute inset-0 rounded-full"
          style={{ border: `1.5px solid ${color}` }}
          initial={{ scale: 0.6, opacity: 0.6 }}
          animate={{ scale: 2.8, opacity: 0 }}
          transition={{
            duration: 2.7,
            ease: 'easeOut',
            repeat: Infinity,
            delay,
          }}
        />
      ))}
    </span>
  );
}
