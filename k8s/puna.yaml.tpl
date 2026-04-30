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
        - name: home
          hostPath:
            path: ${HOST_HOME}
            type: Directory
        - name: litellm-config
          configMap:
            name: puna-litellm-config
        - name: ssh-keys
          emptyDir: {}

      imagePullSecrets:
        - name: ghcr-creds

      initContainers:
        - name: seed-claude-config
          image: ${PUNA_IMAGE}
          imagePullPolicy: Always
          command:
            - sh
            - -c
            - |
              mkdir -p ${HOST_HOME}/.puna
              cp /home/node/.claude/settings.json ${HOST_HOME}/.puna/settings.json
              [ -f ${HOST_HOME}/.puna/.claude.json ]  || cp /home/node/.claude.json ${HOST_HOME}/.puna/.claude.json
              cp /home/node/.claude/CLAUDE.md ${HOST_HOME}/.puna/CLAUDE.md
              cp -r ${HOST_HOME}/.ssh/. /home/node/.ssh/
              chmod 700 /home/node/.ssh
              chmod 600 /home/node/.ssh/*
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsUser: 1000
            runAsGroup: 1000
          volumeMounts:
            - name: home
              mountPath: ${HOST_HOME}
            - name: ssh-keys
              mountPath: /home/node/.ssh
        - name: wait-for-postgres
          image: postgres:16-alpine
          command: ["sh", "-c", "until pg_isready -h puna-postgres -U litellm; do sleep 2; done"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsUser: 999
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
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: DATABASE_URL
              value: "postgresql://litellm:$(POSTGRES_PASSWORD)@puna-postgres:5432/litellm"
            - name: REDIS_HOST
              value: "puna-redis"
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: REDIS_PASSWORD
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
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
            - name: home
              mountPath: ${HOST_HOME}
            - name: home
              mountPath: /home/node/.claude
              subPath: .puna
            - name: home
              mountPath: /home/node/.claude.json
              subPath: .puna/.claude.json
            - name: ssh-keys
              mountPath: /home/node/.ssh
          env:
            - name: CLAUDE_CODE_USE_OPENAI
              value: "1"
            - name: OPENAI_BASE_URL
              value: "http://localhost:4000"
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: puna-secrets
                  key: LITELLM_MASTER_KEY
            - name: OPENAI_MODEL
              value: "deepseek-chat"
            - name: HOST_HOME
              value: "${HOST_HOME}"
            - name: KUBECONFIG
              value: "${HOST_HOME}/.kube/config"
            - name: NODE_OPTIONS
              value: "--max-old-space-size=7000"
            - name: ANTHROPIC_DEFAULT_SONNET_MODEL
              value: "deepseek-chat"
            - name: ANTHROPIC_DEFAULT_SONNET_MODEL_NAME
              value: "DeepSeek V3"
            - name: ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION
              value: "Fast — everyday coding tasks"
            - name: ANTHROPIC_DEFAULT_OPUS_MODEL
              value: "deepseek-reasoner"
            - name: ANTHROPIC_DEFAULT_OPUS_MODEL_NAME
              value: "DeepSeek R1"
            - name: ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION
              value: "Slow — architecture, complex debugging"
            - name: GITHUB_PERSONAL_ACCESS_TOKEN
              valueFrom:
                secretKeyRef:
                  name: puna-github
                  key: GITHUB_PERSONAL_ACCESS_TOKEN
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "3000m"
              memory: "8Gi"
