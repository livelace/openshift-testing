Это продолжение серии из трех статей об автоматизированном тестировании программных продуктов в Openshift Origin. В данной статье будут описаны основные объекты Openshift, а также описаны принципы работы кластера. Я осознано не делаю попытку описать все возможные объекты и их особенности, так как это очень трудоемкая задача, которая выходит за рамки данной статьи.

<cut/>

#### Кластер:

В целом работа кластера Openshift Origin не сильно отличается от других решений. Поступающие задачи распределяются по рабочим узлам на основе их загруженности, данное распределение берет на себя планировщик. 

Для запуска контейнеров требуется Docker образа, которые могут быть загружены из внутреннего или внешнего регистра. Непосредственно запуск контейнеров происходит в различных [контекстах безопасности](https://docs.openshift.org/latest/admin_guide/manage_scc.html) (политики безопасности, которые ограничивают доступ контейнера к различным ресурсам). 

По умолчанию контейнеры из разных проектов могут коммуницировать друг с другом с помощью [overlay сети](https://en.wikipedia.org/wiki/Overlay_network) (выделяется одна большая подсеть, которая разбивается на более мелкие подсети для всех рабочих узлов). Запущенному на рабочем узле контейнеру выделяется IP-адрес из той подсети, которая была назначена данному узлу. Сама overlay сеть построена на базе Open vSwitch, который использует [VXLAN](https://en.wikipedia.org/wiki/Virtual_Extensible_LAN) для связи между рабочими узлами. 

На каждом рабочем узле запускается выделенныё экземпляр [Dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html), который перенаправляет все DNS запросы контейнеров на SkyDNS во внутреннюю сервисную подсеть. 

Если контейнер аварийно завершил свою работу или просто не может быть проинициализирован, то задача по его развертыванию передается на другой рабочий узел.   

Стоит отметить что:

1. SELinux не является строгим условием работы кластера. Отключение оного ([не рекомендуется по соображениям безопасности](https://www.youtube.com/watch?v=giFKMsIH4b0)) привнесет некое увелечение скорости (равно как и отключение мониторинга, кстати) при работе с контейнерами. Если SELinux мешает работе приложения в контейнере, присутствует возможность добавления исключения SELinux непосредственно на рабочем узле кластера. 

2. По умолчанию используется [LVM](https://en.wikipedia.org/wiki/Logical_Volume_Manager_(Linux)) в качестве хранилища Docker Engine. Это далеко не самое быстрое решение, но можно использовать любой другой тип хранилища ([BTRFS](https://docs.docker.com/engine/userguide/storagedriver/btrfs-driver/#prerequisites), например). 

3. Стоит иметь ввиду, что название сервиса (см. Service) - это DNS имя, которое влечет за собой ограничения на длину и допустимые символы.

4. Чтобы сократить временные и аппаратные издержки при сборке Docker образов можно использовать так называемый "слоистый" подход ([multi-stage в Docker](https://docs.docker.com/engine/userguide/eng-image/multistage-build/)). В данном подходе используются базовые и промежуточные образа, которые дополняют друг друга. Имеем базовый образ "centos:7" (полностью обновлен), имеем промежуточный образ "centos:7-tools" (установлены иструменты), имеем финальный образ "centos:7-app" (содержит "centos:7" и "centos:7-tools"). То есть вы можете создавать задачи сборки, которые основываются на других образах (см. BuildConfig).

5. Достаточно гибким решением является подход, когда существует один проект, который занимается только сборкой Docker образов с последующей "линковкой" данных образов в другие проекты (см. ImageStream). Это позволяет не плодить лишних сущностей в каждом проекте и приведет к некой унификации. 

6. Большинству объектов в кластере можно присвоить произвольные метки, с помощью которых можно совершать массовые операции над данными объектами (удаление определенных контейнеров в проекте, например).

7. Если приложению требуется некий ядерный функционал ядра Linux, то тогда требуется загрузить данный модуль на всех рабочих узлах, где требуется запуск данного приложения.

8. Стоит сразу побеспокоиться об удалении старых образов и забытых окружений. Если первое решается с помощью сборщика мусора/oadm prune, то второе требует проработки и ознакомлении всех участников с правилами совместной работы в Openshift Origin.

9. Любой кластер ограничен ресурсами, поэтому очень желательно организовать мониторинг хотя бы на уровне рабочих узлов (возможен мониторинг на уровне приложения в контейнере). Сделать это можно как с помощью готового решения [Openshift Metrics](https://github.com/openshift/origin-metrics), так и с помощью сторонних решений ([Sysdig](https://www.sysdig.org/), например). При наличии метрик загруженности кластера (в целом или по проектно) можно организовать гибкую диспетчерезацию поступающих задач. 

10. Особенно хочется отметить тот факт, что рабочие узлы могут быть динамически проинициализированы, а это значит, что вы можете расширить свой кластер Openshift Origin на существующих мощностях IaaS. То есть, во время предрелизного тестирования вы можете существенно расширить свои мощности и скоратить время тестирования.
<br>

#### Объекты:

**Project** - объект является [Kubernetes namespace](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/). Верхний уровень абстракции, который содержит другие объекты. Созданные в проекте объекты не пересекаются с объектами в других проектах. На проект могут быть выставлены квоты, привилегии, метки узлов кластера и т.д. Вложенная иерархия и наследование между проектами отсутствуют, доступна плоская структура проектов. Существуюет несколько системных проектов (kube-system, openshift, openshift-infra), которые предназначены для нормального функционирования кластера.

Создание нового проекта:

```
oc adm new-project project1 --node-selector='node_type=minion'
```

Редактирование настроек проекта:

```
oc edit namespace project1
```

```yaml
# Please edit the object below. Lines beginning with a '#' will be ignored,
# and an empty file will abort the edit. If an error occurs while saving this file will be
# reopened with the relevant failures.
#
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    openshift.io/description: ""
    openshift.io/display-name: ""
    openshift.io/node-selector: node_type=minion
...
```
<br>

**Pod** - объект, который стал одним из решающих факторов, так как позволяет запускать произвольные команды внутри контейнера с помощью специальных хуков (и не только). Pod является основной рабочей единицей в кластере. Любой запущенный в кластере контйенер - Pod. По своей сути - группа из одного и более контейнеров, которые работают в единых для этих контейнеров [namespaces (network, ipc, uts, cgroup)](https://lwn.net/Articles/531114/), используют общее хранилище данных, секреты. Контейнеры, из которых состоит Pod, всегда запущены на одном узле кластера, а не распределены в одинаковых пропорциях по всем узлам (если Pod будет состоять из 10 контейнеров, все 10 будут работать на одном узле). 


Pod:

```yaml
apiVersion: "v1"
kind: "Pod"
metadata:
  name: "nginx-redis"
spec:
  containers:
    -
      name: "nginx"
      image: "nginx:latest"
      
    -
      name: "redis"
      image: "redis:latest"
```

Статус Pod:

```
NAME          READY     STATUS    RESTARTS   AGE
nginx-redis   2/2       Running   0          7s
```
<br>

**Secret** - может являться строкой или файлом, предназначен для проброса чувствительной (хранится в открытом виде в etcd ([поддержка шифрования в Kubernetes 1.7](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/))) информации в Pod. Один Secret может содержать множество значений.

Создание Secret:

```
oc secrets new gitconfig .gitconfig=/home/user/.gitconfig
```

Использование Secret в BuildConfig:

```yaml
apiVersion: "v1"
kind: "BuildConfig"
metadata:
  name: "nginx-bc"
spec:
  source:
    type: "Git"
    git:
      uri: "https://github.com/username/nginx.git"
    sourceSecret:
      name: "gitconfig"
      
  strategy:
    type: "Docker"
    dockerStrategy:
      dockerfilePath: docker/nginx-custom
      noCache: true
      
  output:
    to:
      kind: "ImageStreamTag"
      name: "nginx-custom:latest"
```

<br>

**ServiceAccount** - специальный тип объекта, который предназначен для взаимодействия с ресурсам кластера. По своей сути является системным пользователем.

По умолчанию новый проект содержит три ServiceAccount: 

* builder - отвечает за сборку Docker образов и их выгрузку в регистр (см. BuildConfig).
* deployer - от этого аккаунта запускаются задачи развертывания (см. DeploymentConfig).
* default - все остальные Pod (которые не относятся к задачам развертывания) запускаются именно от этого аккаунта.

Перечисленные служебные аккаунты:
 
 1. Cодержат автоматически созданные секреты, которые используются для доступа к ресурсам кластера.
 2. Обладают ролями, которые позволяют им осуществлять те или иные действия в кластере.

ServiceAccount:

```yaml
apiVersion: "v1"
kind: "ServiceAccount"
metadata:
  name: "jenkins"
```

Свойства ServiceAccount:

```
Name:           jenkins
Namespace:      project1
Labels:         <none>

Image pull secrets:     jenkins-dockercfg-pvgsr

Mountable secrets:      jenkins-dockercfg-pvgsr
                        jenkins-token-p8bwz

Tokens:                 jenkins-token-p8bwz
                        jenkins-token-zsn9p
```

Добавление прав администратора проекта ServiceAccount: 

```
oc policy add-role-to-user admin system:serviceaccount:project1:jenkins
```
<br>

**DeploymentConfig** - это объект, который оперирует всё теми же Pod, но при этом привносит ряд дополнительных механизмов для управления жизненным циклом запущенных приложений, а именно:

1. Добавляет стратегию развертывания, т.е. позволяет определить каким образом будет: обновлено приложение при выходе новой версии, произведен откат к работающей версии в случае неудачи.
2. Позволяет установить триггеры, которые вызовут повторное развертывание конфигурации.
3. Позволяет указать количество экземпляров/реплик приложения.

DeploymentConfig:

```yaml
apiVersion: "v1"
kind: "DeploymentConfig"
metadata:
  name: "nginx-dc"
spec:
  template:
    metadata:
      labels:
        name: "nginx-dc"
    spec:
      containers:
        -
          name: "nginx"
          image: "nginx:latest"

  replicas: 3

  selector:
    name: "nginx-dc"
```

Статус DeploymentConfig:

```
NAME               READY     STATUS    RESTARTS   AGE
nginx-dc-1-1wl8m   1/1       Running   0          7s
nginx-dc-1-k3mss   1/1       Running   0          7s
nginx-dc-1-t8qf3   1/1       Running   0          7s
```
<br>

**ImageStream** - по своей сути является "контейнером" для "ссылок" (ImageStreamTag), которые указывают на Docker образа или другие ImageStream.


ImageStream:

```yaml
apiVersion: "v1"
kind: "ImageStream"
metadata:
  name: "third-party"
```

Создание тага/ссылки на Docker образ между проектами:

```
oc tag project2/app:v1 project1/third-party:app
```

Создание тага/ссылки на Docker образ, который расположен на Docker Hub:

```
oc tag --source=docker nginx:latest project1/third-party:nginx
```
<br>

**BuildConfig** - объект является сценарием того, как будет собран Docker образ и куда он будет помещен. Сборка нового образа может базироваться на других образах, за это отвечает секция "from:"

Источники сборки (то место, где размещены исходные данные для сборки): 

* Binary
* Dockerfile
* Git
* Image 
* Input Secrets
* External artifcats

Стратегии сборки (каким образом следует интерпретировать источник данных): 

* Custom
* Docker
* Pipeline
* S2I
 
Назначение сборки (куда будет выгружен собранный образ):

* DockerImage
* ImageStreamTag

 
BuildConfig:
 
```yaml
apiVersion: "v1"
kind: "BuildConfig"
metadata:
  name: "nginx-bc"
spec:
  source:
    type: "Git"
    git:
      uri: "https://github.com/username/nginx.git"
      
  strategy:
    type: "Docker"
    dockerStrategy:
      from:
        kind: "ImageStreamTag"
        name: "nginx:latest"
        
      dockerfilePath: docker/nginx-custom
      noCache: true
      
  output:
    to:
      kind: "ImageStreamTag"
      name: "nginx-custom:latest"
```

Какие операции выполнит данный BuildConfig:

1. Возьмет за основу ImageStream "nginx:latest"
2. Склонирует Git репозиторий, найдет в данном репозитории файл docker/nginx-custom, загрузит из данного файла Dockerfile инструкции, выполнит данные инструкции над базовым образом.
3. Результирующий образ поместит в ImageStream "nginx-custom:latest"

<br>

**Service** - объект, который стал одним из решающих факторов при выборе системы запуска сред, так как он позволяет гибко настраивать коммуникации между средами (что очень важно в тестировании). В случаях с использованием других систем требовались подготовительные манипуляции: выделить диапазоны IP-адресов, зарегистрировать DNS имена, осуществить проброс портов и т.д. и т.п. Service может быть объявлен до фактического развертывания приложения.

Что происходит во время публикации сервиса в проекте:

1. Для сервиса выделяется IP-адрес из специальной сервисной подсети.
2. Регистрируется DNS имя данного сервиса. Все Pod в проекте, которые были запущены до/после публикации сервиса, смогут разрешать данное DNS имя.
3. Все Pod в проекте, которые будут запущены после публикации сервиса, получат список переменных окружения, которые содержат IP-адрес и порты опубликованного сервиса.

Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: "nginx-svc"
spec:
  selector:
    name: "nginx-pod"
  ports:
    - port: 80
      targetPort: 80
      name: "http"
       
    - port: 443
      targetPort: 443
      name: "https"
```

Разрешение DNS имени:

```
root@nginx-pod:/# ping nginx-svc              
PING nginx-svc.myproject.svc.cluster.local (172.30.217.250) 56(84) bytes of data.
```

Переменные окружения:

```
root@nginx-pod:/# env | grep -i nginx
NGINX_SVC_PORT_443_TCP_ADDR=172.30.217.250
HOSTNAME=nginx-pod
NGINX_VERSION=1.13.1-1~stretch
NGINX_SVC_PORT_80_TCP_PORT=80
NGINX_SVC_PORT_80_TCP_ADDR=172.30.217.250
NGINX_SVC_SERVICE_PORT=80
NGINX_SVC_PORT_80_TCP_PROTO=tcp
NGINX_SVC_PORT_443_TCP=tcp://172.30.217.250:443
NGINX_SVC_SERVICE_HOST=172.30.217.250
NGINX_SVC_PORT_443_TCP_PROTO=tcp
NGINX_SVC_SERVICE_PORT_HTTPS=443
NGINX_SVC_PORT_443_TCP_PORT=443
NGINX_SVC_PORT=tcp://172.30.217.250:80
NGINX_SVC_SERVICE_PORT_HTTP=80
NGINX_SVC_PORT_80_TCP=tcp://172.30.217.250:80
```

**Заключение:**

Все объекты кластера можно описать с помощью YAML, это, в свою очередь, дает возможность полностью автоматизировать любые процессы, которые протекают в Openshift Origin. Вся сложность в работе с кластером заключается в знании приципов работы и механизмов взаимодействия объектов. Такие рутинные операции как инициализация новых рабочих узлов берут на себя сценарии Ansible. Доступность API открывает возможность работать с кластером напрямую минуя посредников. 


