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
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: REDIS_PASSWORD

      containers:
        - name: litellm
          image: ghcr.io/berriai/litellm:main-v1.83.10
          args:
            - "--config"
            - "/etc/litellm/config.yaml"
            - "--host"
            - "127.0.0.1"
            - "--port"
            - "4000"
          ports:
            - containerPort: 4000
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
            httpGet:
              path: /health
              port: 4000
              host: 127.0.0.1
            initialDelaySeconds: 15
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 4000
              host: 127.0.0.1
            initialDelaySeconds: 10
            periodSeconds: 10

        - name: claudex
          image: ${PUNA_IMAGE}
          imagePullPolicy: Always
          stdin: true
          tty: true
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
