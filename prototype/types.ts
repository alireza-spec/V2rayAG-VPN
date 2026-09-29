export type VPNServer = {
  id: string;
  name: string;
  country: string;
  endpointIp: string;
  city: string;
  flag: string;
  protocol: string;
  ping: number;
  load: number;
  group: string;
};

export type VPNSubscription = {
  id: string;
  name: string;
  url: string;
  protocolLabel: string;
};
