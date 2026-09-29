import React from 'react';
import { Shield } from 'lucide-react';

export const BrandMark: React.FC<{ small?: boolean }> = ({ small = false }) => (
  <div className={`brand-mark ${small ? 'brand-mark-small' : ''}`} aria-label="V2rayAG VPN logo">
    <div className="brand-mark-glow" />
    <Shield size={small ? 21 : 27} strokeWidth={2.1} />
    <span className="brand-mark-check">✦</span>
  </div>
);
