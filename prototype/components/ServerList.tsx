import React from 'react';
import { Check, ChevronRight, MapPin, Search, Signal } from 'lucide-react';
import { VPNServer } from '../types';

type Props = { servers: VPNServer[]; selectedId: string; onSelect: (server: VPNServer) => void; query: string; onQuery: (value: string) => void; compact?: boolean };

export const ServerList: React.FC<Props> = ({ servers, selectedId, onSelect, query, onQuery, compact = false }) => (
  <section className="panel server-panel">
    <div className="panel-heading">
      <div><div className="eyebrow">LOCATIONS</div><h3>{compact ? 'Quick select' : 'Choose your location'}</h3></div>
      <span className="muted-count">{servers.length} locations</span>
    </div>
    {!compact && <label className="server-search"><Search size={16} /><input value={query} onChange={e => onQuery(e.target.value)} placeholder="Search country or city" /></label>}
    <div className="server-list">
      {servers.map(server => <button className={`server-row ${selectedId === server.id ? 'selected' : ''}`} key={server.id} onClick={() => onSelect(server)}>
        <span className="server-flag">{server.flag}</span>
        <span className="server-main"><strong>{server.city}</strong><small>{server.country} <span className="protocol-tag">{server.protocol}</span></small></span>
        <span className="server-stats"><span className="ping-good"><Signal size={13} />{server.ping}<small>ms*</small></span><span className="server-load"><i style={{ width: `${server.load}%` }} />{server.load}%</span></span>
        {selectedId === server.id ? <span className="selected-check"><Check size={15} /></span> : <ChevronRight size={16} className="row-chevron" />}
      </button>)}
      {servers.length === 0 && <div className="empty-state"><MapPin size={18} />No matching locations.</div>}
    </div>
    <p className="footnote">* Sample latency values for the prototype—not live measurements.</p>
  </section>
);
