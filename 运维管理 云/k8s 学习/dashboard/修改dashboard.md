1. 我们是 wget 官方文件，进行了一定的修改

   ```shell
   wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.2.0/aio/deploy/recommended.yaml
   ```

2. 通过vim 修改。

   主要增加了一个对外开放的端口，以及volume映射

   ```shell
   ports:
   	- containerPort: 8443
   	protocol: TCP
   	hostPort: 8080
   args:
   	- --auto-generate-certificates
   	- --namespace=kubernetes-dashboard
   	- --tls-cert-file=/certs/dashboard.crt
   	- --tls-key-file=/certs/dashboard.key
   ```

   ```shell
   ```

   

