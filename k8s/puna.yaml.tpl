apiVersion: apps/v1
kind: Deployment
metadata:
  name: puna
  namespace: puna
spec:
  replicas: 1
  selector:
    matchLabels:
      app: puna
  template:
    metadata:
      labels:
        app: puna
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: puna-workspace
        - name: litellm-config
          configMap:
            name: puna-litellm-config

      imagePullSecrets:
        - name: ghcr-creds

      initContainers:
        - name: wait-for-redis
          image: redis:7-alpine
          command: ["sh", "-c", "until redis-cli --no-auth-warning -a $REDIS_PASSWORD -h puna-redis ping; do sleep 2; done"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsUser: 999
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: REDIS_PASSWORD

      containers:
        - name: litellm
          image: ghcr.io/berriai/litellm:main-v1.83.7-stable.patch.1
          args:
            - "--config"
            - "/etc/litellm/config.yaml"
            - "--host"
            - "127.0.0.1"
            - "--port"
            - "4000"
          ports:
            - containerPort: 4000
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsNonRoot: false
          volumeMounts:
            - name: litellm-config
              mountPath: /etc/litellm
          env:
            - name: DEEPSEEK_API_KEY
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: DEEPSEEK_API_KEY
            - name: LITELLM_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: LITELLM_MASTER_KEY
            - name: REDIS_HOST
              value: "puna-redis"
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: REDIS_PASSWORD
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          livenessProbe:
            exec:
              command: ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4000/health/liveliness')"]
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            exec:
              command: ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4000/health/liveliness')"]
            initialDelaySeconds: 10
            periodSeconds: 10

        - name: claudex
          image: ${PUNA_IMAGE}
          imagePullPolicy: Always
          stdin: true
          tty: true
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
          volumeMounts:
            - name: workspace
              mountPath: /workspace
          env:
            - name: CLAUDE_CODE_USE_OPENAI
              value: "1"
            - name: OPENAI_BASE_URL
              value: "http://localhost:4000"
            - name: OPENAI_API_KEY
              value: "sk-puna-local"
            - name: OPENAI_MODEL
              value: "deepseek-chat"
            - name: NODE_OPTIONS
              value: "--max-old-space-size=2048"
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "3000m"
              memory: "4Gi"
