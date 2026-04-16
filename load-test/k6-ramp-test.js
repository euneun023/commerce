import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    ramping_load: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 3000,
      stages: [
        { target: 100, duration: '2m' },
        { target: 1000, duration: '3m' },
        { target: 3000, duration: '3m' },
        { target: 5000, duration: '3m' },
        { target: 1000, duration: '2m' },
        { target: 100, duration: '2m' }
      ]
    }
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000']
  }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost';

export default function () {
  const res = http.get(`${BASE_URL}/healthz`);

  check(res, {
    'status is 200': (r) => r.status === 200,
  });
