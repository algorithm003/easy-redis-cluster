import http.server
import os
import ssl
import json

from rediscluster import RedisCluster
from rediscluster.exceptions import RedisClusterException

log_file = 'log'


class Webhook(object):
    SEP, CONN, CONNS = '-', None, list()

    MIN_POD_REPLICAS = int(os.environ.get('REDIS_NODE_MIN_POD_REPLICAS') or 6)
    CLIENT_PORT = int(os.environ.get('REDIS_NODE_CLIENT_PORT') or 6379)
    KEY_NAMESPACE = os.environ.get('REDIS_NODE_KEY_NAMESPACE') or 'redis-cluster'
    SCALE_DOWN_KEY = os.environ.get('REDIS_NODE_SCALE_DOWN_KEY') or 'scale-down'
    NAME = os.environ.get('REDIS_NODE_NAME') or 'redis-node'
    POD_HOST_END_PART = os.environ.get('REDIS_NODE_POD_HOST_END_PART') or 'redis-node-svc.redis-cluster-dev.svc.cluster.local'
    HOST_TPL = f'{NAME}-{{}}.{POD_HOST_END_PART}'

    def __init__(self, redis_node_index):
        self.index = int(redis_node_index)
        self.key = f'{self.KEY_NAMESPACE}:{self.SCALE_DOWN_KEY}'
        if not self.CONN and not self.CONNS:
            self.CONN = self._get_conn()
            self.CONNS += self.CONN,
        else:
            self.CONN = self.CONNS[0]

    def process(self):
        if not self._can_scale_down():
            return False

        allowed = False
        index, status = self._get_scale_down_status()
        os.system(f'echo "index: {index} status: {status}" >> {log_file}')
        if status is None:
            self._notify_redis_node_scaler()
        if status == ScaleDownStatus.FINISHED:
            allowed = True if self._clear_scale_down_status() and self._check_redis_node_index(index) else False
        return self._feedback_to_kubernetes_cluster(allowed)

    def _feedback_to_kubernetes_cluster(self, allowed):
        return allowed

    def _notify_redis_node_scaler(self):
        if self.CONN:
            self.CONN.setnx(self.key, self._ready_data())

    def _get_scale_down_status(self):
        if self.CONN:
            data = self.CONN.get(self.key)
            if data:
                return self._parse_data(data)
            return -1, None
        return -1, 0

    def _clear_scale_down_status(self):
        return self.CONN.delete(self.key) if self.CONN else 0

    def _parse_data(self, data):
        try:
            index, status = data.decode().split(self.SEP)
            return int(index), int(status)
        except (AttributeError, TypeError, ValueError):
            return -1, 0

    def _ready_data(self):
        # format: redis_node_index - status, example: 6-1
        return self.SEP.join((str(self.index), str(ScaleDownStatus.NEED_TO_SCALE_DOWN)))

    def _check_redis_node_index(self, index_from_scaler):
        if index_from_scaler == self.index:
            return True
        return False

    def _can_scale_down(self):
        if self.index < self.MIN_POD_REPLICAS:
            return False
        return True

    def _get_conn(self):
        for i in range(self.MIN_POD_REPLICAS):
            try:
                return RedisCluster(
                    host=self.HOST_TPL.format(i),
                    port=self.CLIENT_PORT,
                    max_connections=1,
                )
            except RedisClusterException:
                pass
        else:
            return None


class ScaleDownStatus(object):
    NEED_TO_SCALE_DOWN = int(os.environ.get('REDIS_NODE_SCALE_DOWN_STATUS__NEED_TO_SCALE_DOWN') or 1)  # 1
    SCALING = int(os.environ.get('REDIS_NODE_SCALE_DOWN_STATUS__SCALING') or 2)  # 2
    FINISHED = int(os.environ.get('REDIS_NODE_SCALE_DOWN_STATUS__FINISHED') or 3)  # 3


class SimpleHandler(http.server.BaseHTTPRequestHandler):
    RESPONSE = {
        'apiVersion': '',
        'kind': '',
        'response': {
            'uid': '',
            'allowed': '',
        }
    }

    def do_POST(self):

        try:
            request = json.loads(self.rfile.read(int(self.headers['Content-Length'])).decode())

            redis_node_index = int(request['request']['name'].split('-')[-1])

            allowed = Webhook(redis_node_index).process()

            self._gen_response(request, allowed)
            self._return(200)

        except (json.decoder.JSONDecodeError, AttributeError, TypeError, ValueError):
            self._gen_response(request, True)
            self._return(200)

    def _gen_response(self, request, allowed):
        self.RESPONSE['apiVersion'] = request['apiVersion']
        self.RESPONSE['kind'] = request['kind']
        self.RESPONSE['response']['uid'] = request['request']['uid']
        self.RESPONSE['response']['allowed'] = allowed

    def _return(self, code):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(self.RESPONSE).encode())


if __name__ == '__main__':
    port = os.environ.get('WEBHOOK_PORT') or 443
    vol = os.environ.get('WEBHOOK_VOL_TLS_NAME') or 'tls'
    key = os.environ.get('WEBHOOK_KEY_FILE_NAME') or 'tls.key'
    crt = os.environ.get('WEBHOOK_CRT_FILE_NAME') or 'tls.crt'

    httpd = http.server.HTTPServer(('0.0.0.0', int(port)), SimpleHandler)
    httpd.socket = ssl.wrap_socket(
        httpd.socket,
        keyfile=f'/{vol}/{key}',
        certfile=f'/{vol}/{crt}',
        server_side=True,
    )
    httpd.serve_forever()
