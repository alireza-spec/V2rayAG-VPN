import React from 'react';
import { ArrowDown, ArrowUp, MapPin, Power, ShieldCheck, Signal } from 'lucide-react';
import { VPNServer } from '../types';

type Props = { connected: boolean; connecting: boolean; server: VPNServer; transport: string; duration: string; onToggle: () => void };

export const ConnectCard: React.FC<Props> = ({ connected, connecting, server, transport, duration, onToggle }) => {
  const status = connecting ? 'Connecting' : connected ? 'Connected' : 'Disconnected';
  return <section className={`connect-card ${connected ? 'is-connected' : ''} ${connecting ? 'is-connecting' : ''}`}>
    <div className="connect-stage">
      <div className="stage-orbit stage-orbit-one" />
      <div className="stage-orbit stage-orbit-two" />
      <button className={`power-button ${connected ? 'power-on' : ''}`} onClick={onToggle} disabled={connecting} aria-label={connected ? 'Disconnect demo connection' : 'Connect demo connection'}>
        <span className="power-ring"><Power size={34} strokeWidth={2} /></span>
      </button>
      <div className="stage-status"><span className={`status-dot ${connected ? 'online' : ''}`} />{status}</div>
      <p className="stage-caption">{connecting ? 'Preparing your secure route…' : connected ? 'Demo session active' : 'Tap to connect securely'}</p>
    </div>

    <div className="connection-details-card">
      <div className="session-head"><div><span className="detail-label">CONNECTED FOR</span><strong className="session-time">{duration}</strong></div><span className="session-shield"><ShieldCheck size={15} />{connected ? 'Preview session' : 'Ready when you are'}</span></div>
      <div className="destination-chip"><div><span>DESTINATION IP</span><strong>{server.endpointIp}</strong></div><span className="destination-country"><span>{server.flag}</span>{server.country}</span><small>sample</small></div>
      <div className="traffic-row">
        <div className="traffic-metric"><span className="traffic-icon down"><ArrowDown size={15} /></span><div><strong>0 B/s</strong><small>Download</small></div></div>
        <div className="traffic-divider" />
        <div className="traffic-metric"><span className="traffic-icon up"><ArrowUp size={15} /></span><div><strong>0 B/s</strong><small>Upload</small></div></div>
      </div>
      <div className="connection-route-strip"><div className="route-info"><span className="route-flag">{server.flag}</span><div><strong>{server.city}, {server.country}</strong><small><MapPin size={11} /> {server.protocol} · {transport === 'Automatic' ? 'Auto' : transport}</small></div></div><div className="route-ping"><span><Signal size={13} /> {server.ping} ms</span><small>sample</small></div></div>
      <div className="demo-disclaimer"><span className="demo-dot" /> Preview only · no VPN traffic is routed</div>
    </div>
  </section>;
};
