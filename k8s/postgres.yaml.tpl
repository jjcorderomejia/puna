apiVersion: apps/v1
kind: Deployment
metadata:
  name: puna-postgres
  namespace: puna
spec:
  replicas: 1
  selector:
    matchLabels:
      app: puna-postgres
  template:
    metadata:
      labels:
        app: puna-postgres
    spec:
      securityContext:
        fsGroup: 999
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: puna-postgres-data
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - name: POSTGRES_DB
              value: litellm
            - name: POSTGRES_USER
              value: litellm
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: puna-postgres-secret
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            runAsNonRoot: true
            runAsUser: 999
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "litellm", "-d", "litellm"]
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: puna-postgres
  namespace: puna
spec:
  selector:
    app: puna-postgres
  ports:
    - port: 5432
      targetPort: 5432
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: puna-postgres-data
  namespace: puna
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ${STORAGE_CLASS}
