Здравствуйте, уважаемые участники ИТ сообщества. Данный материал является незапланированным продолжением серии статей ([первая статья](https://habrahabr.ru/post/332994/), [вторая статья](https://habrahabr.ru/post/333012/), [третья статья](https://habrahabr.ru/post/333014/)), которые посвящены тестированию ПО в [Openshift Origin](https://habrahabr.ru/post/333014/).  В данной статье будут рассмотрены аспекты интеграции контейнеров и виртуальных машин посредством Openshift и [Openstack](http://openstack.org/).

Какие цели я преследовал интегрируя Openshift с Openstack:

1. Добавить возможность запускать контейнеры и виртуальные машины в единой сети ([L2](https://en.wikipedia.org/wiki/OSI_model), отсутствие вложенных сетей).
2. Добавить возможность использования опубликованных в Openshift сервисов виртуальными машинами.
3. Добавить возможность интеграции физического сегмента сети с сетью контейнеров/виртуальных машин. 
4. Иметь возможность обоюдного разрешения [FQDN](https://en.wikipedia.org/wiki/Fully_qualified_domain_name) для контейнеров и виртуальных машин.
5. Иметь возможность встроить процесс развертывания гибридных окружений (контейнеры, виртуальные машины) в существующий [CI](https://en.wikipedia.org/wiki/Continuous_integration)/[CD](https://en.wikipedia.org/wiki/Continuous_delivery#Relationship_to_continuous_deployment).

*Примечание: в данной статье не пойдет речи об автоматическом масштабировании кластера и предоставлении хранилищ данных.*

<cut/>

Своими словами о программном обеспечении, которое способствовало достижению поставленных целей:

1. Openstack - операционная система для создания облачных сервисов. Мощный конструктор, который собрал под своё начало множество проектов и вендоров. По моему личному мнению конкурентов Openstack на рынке [private cloud](https://en.wikipedia.org/wiki/Cloud_computing#Private_cloud) просто нет. Инсталяции Openstack могут быть очень гибкими и многоэлементными, с поддержкой различных гипервизоров и сервисов. Доступны плагины Jenkins[[1]](https://wiki.jenkins.io/display/JENKINS/Openstack+Cloud+Plugin)[[2]](https://wiki.jenkins.io/display/JENKINS/Openstack+Heat+Plugin). Поддерживается [оркестрация](https://wiki.openstack.org/wiki/Heat), [workflow](https://wiki.openstack.org/wiki/Mistral), [multi tenancy](https://wiki.openstack.org/wiki/HierarchicalMultitenancy), [zoning](https://www.mirantis.com/blog/the-first-and-final-word-on-openstack-availability-zones/) и т.д.

2. Openshift Origin - standalone решение от Red Hat (в противовес [Openshift Online и Openshift Dedicated](https://en.wikipedia.org/wiki/OpenShift)) предназаченное для оркестрации контейнеров. Решение построено на базе [Kubernetes](https://en.wikipedia.org/wiki/Kubernetes), но обладает рядом преимуществ/дополнений, которые обеспечивают удобство и эффективность работы. 

3. [Kuryr](https://wiki.openstack.org/wiki/Kuryr) - молодой проект Openstack (большой плюс в том, что разработка ведется в экосистеме Openstack), позволяет различными способами интегрировать контейнеры (nested, baremetal) в сеть [Neutron](https://wiki.openstack.org/wiki/Neutron). Является простым и надежным решением c далеко идущими планами по расширению функционала. На текущий момент на рынке представлено множество решений [NFV](https://en.wikipedia.org/wiki/Network_function_virtualization)/[SDN](https://en.wikipedia.org/wiki/Software-defined_networking) (коим Kuryr не является), большая часть из которых может быть исключена как не поддерживаемая Openstack/Openshift нативно, но даже существенно сократив список остаются решения, которые весьма богаты функционально, нр при этом являются достаточно сложными с точки зрения интеграции и сопровождения ([OpenContrail](http://www.opencontrail.org/), [MidoNet](https://www.midonet.org/), [Calico](https://www.projectcalico.org/), [Contiv](https://contiv.github.io/), [Weave](https://www.weave.works/)). Kuryr же позволяет без особых трудностей интегрировать контейнеры Openshift ([CNI](https://github.com/containernetworking/cni) плагин) в сеть Neutron (классический сценарии с [OVS](http://openvswitch.org/)).


#### Типовые схемы интеграции:
<br>

**1. Кластер Openshift размещен в облаке Openstack**

![](https://habrastorage.org/webt/59/d7/22/59d7223162d12820132795.png)

Схема интеграции, когда все элементы расположены в облаке Openstack, весьма привлекательна и удобна, но главный минус данной схемы заключается в том, что контейнеры запускаются в виртуальных машинах и все преимущества в скорости сводятся на нет.

![](https://habrastorage.org/webt/59/d7/22/59d72231a1687327390548.png)

При данной схеме интеграции рабочим узлам Openshift назначается [TRUNK](https://wiki.openstack.org/wiki/Neutron/TrunkPort) порт, который содержит некоторое количество SUBPORT. Каждый SUBPORT содержит индетификатор [VLAN](https://en.wikipedia.org/wiki/Virtual_LAN). Если TRUNK порт находится в одной сети, то SUBPORT находится в другой. SUBPORT стоит рассматривать как мост между двумя сетями. При поступлении Ethernet кадра в TRUNK c меткой VLAN (которая соотвествует некому SUBPORT), то такой кадр будет направлен в соотвествующий SUBPORT. Из всего этого следует, что на рабочем узле Openshift создается обычный VLAN, который помещается в [network namespace](https://en.wikipedia.org/wiki/Linux_namespaces) контейнера. 

**2. Рабочие ноды Openshift кластера являются физическими серверами, master размещен в облаке Openstack**

![](https://habrastorage.org/webt/59/d7/22/59d7223193c10069302387.png)

Схема интеграции, когда контейнеры запущены на выделенных серверах, не сложнее схемы со всеми элементами расположенными в облаке Openstack. [VXLAN](https://en.wikipedia.org/wiki/Virtual_Extensible_LAN) позволяет организовать виртуальные сети без необходимости сегментирования сети предприятия. 

![](https://habrastorage.org/webt/59/d7/22/59d722310847e809665630.png)

При данной схеме интеграции на рабочих узлах Openshift работает [Open vSwitch Agent](https://docs.openstack.org/liberty/networking-guide/scenario-classic-ovs.html), который интегрирован c Neutron. Запущенному контейнеру назначается [VETH](https://lwn.net/Articles/232688/) устройство, которое работает напрямую с мостом Open vSwitch, то есть контейнер интегрируется в сеть Neutron напрямую. В последующем Open vSwitch Agent инициирует VXLAN соединение с Neutron Router для последущей маршрутизации пакетов.

**Роль Kuryr во всех вариантах сводится к:**

1. При создании контейнера будет задействован kuryr CNI плагин, который отправит запрос (все коммуникации осуществляются через стандартный API Openshift/Kubernetes) kuryr-controller на подключение к сети.
2. kuryr-controller получив запрос "попросит" Neutron выделить порт. После инициализации порта, kuryr-controller передаст сетевую конфигурацию обратно CNI плагину, которая и будет применена к контейнеру.

#### Интеграция физического сегмента сети c сетью контейнеров и виртуальных машин:

![](https://habrastorage.org/webt/59/d7/22/59d7223200f27949836636.png)

В самом простом варианте участники разработки имеют машрутизируемый доступ в сеть контейнеров и виртуальных мышин посредством Neutron Router, для этого достаточно прописать на рабочих станциях адрес шлюза для нужной подсети. Данную возможность трудно переоценить с точки зрения тестирования, так как стандартные механизмы ([hostNetwork, hostPort, NodePort, LoadBalancer, Ingress](http://alesnosek.com/blog/2017/02/14/accessing-kubernetes-pods-from-outside-of-the-cluster/)) Openshift/Kubernetes явно ограничены в возможностях, равно как и [LBaaS](https://wiki.openstack.org/wiki/Neutron/LBaaS) в Openstack. 

Особенно трудно переоценить возможность разворачивать и иметь доступ к нужным приложениям, каталог которых доступен через веб-интерфейс Openshift (если такие проекты как [Monocular](https://github.com/kubernetes-helm/monocular) начали появляться сравнительно недавно, то в Openshift данный функционал присутствует с первых версий). Любой участник разработки может развернуть доступное приложение не тратя времени на изучение [Docker](http://docker.io/), Kubernetes, самого приложения.

#### Разрешение FQDN контейнеров и виртуальных машин:

В случае с контейнерами всё очень просто, для каждого опубликованного сервиса создается FQDN запись во внутреннем DNS сервере по следующей схеме:

```<service>.<pod_namespace>.svc.cluster.local```

В случае с виртуальными машинами используется расширение [dns](https://docs.openstack.org/mitaka/networking-guide/config-dns-int.html) для [ml2](https://wiki.openstack.org/wiki/Neutron/ML2) плагина:

```extension_drivers = port_security,dns```

При создании порта в Neutron задается аттрибут dns_name, которой и формирует FQDN:

```
[root@openstack ~]# openstack port create --dns-name hello --network openshift-pod hello   
+-----------------------+---------------------------------------------------------------------------+
| Field                 | Value                                                                     |
+-----------------------+---------------------------------------------------------------------------+
| admin_state_up        | UP                                                                        |
| allowed_address_pairs |                                                                           |
| binding_host_id       |                                                                           |
| binding_profile       |                                                                           |
| binding_vif_details   |                                                                           |
| binding_vif_type      | unbound                                                                   |
| binding_vnic_type     | normal                                                                    |
| created_at            | 2017-10-04T15:25:21Z                                                      |
| description           |                                                                           |
| device_id             |                                                                           |
| device_owner          |                                                                           |
| dns_assignment        | fqdn='hello.openstack.local.', hostname='hello', ip_address='10.42.0.15'  |
| dns_name              | hello                                                                     |
| extra_dhcp_opts       |                                                                           |
| fixed_ips             | ip_address='10.42.0.15', subnet_id='4e82d6fb-9613-4606-a3ae-79ed8de42eea' |
| id                    | adfa0aab-82c6-4d1e-bec3-5d2338a48205                                      |
| ip_address            | None                                                                      |
| mac_address           | fa:16:3e:8a:94:38                                                         |
| name                  | hello                                                                     |
| network_id            | 050a8277-e4b3-4927-9762-d74274d9c8ff                                      |
| option_name           | None                                                                      |
| option_value          | None                                                                      |
| port_security_enabled | True                                                                      |
| project_id            | 2823b3394572439c804d56186cc82abb                                          |
| qos_policy_id         | None                                                                      |
| revision_number       | 6                                                                         |
| security_groups       | 3d354277-2aec-4bfb-91ac-d320bfb6c90f                                      |
| status                | DOWN                                                                      |
| subnet_id             | None                                                                      |
| updated_at            | 2017-10-04T15:25:21Z                                                      |
+-----------------------+---------------------------------------------------------------------------+
```
 
FQDN для виртуальной машины может быть разрешен с помощью DNS сервера, который обслуживает [DHCP](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol) для данной сети.

Остается лишь разместить на Openshift master (или в любом другом месте) DNS resolver, который будет разрешать ```*.cluster.local``` с помощью [SkyDNS Openshift](https://docs.openshift.org/latest/architecture/networking/networking.html), а ```*.openstack.local``` с помощью DNS сервера сети Neutron.


#### Демонстрация:

<oembed>https://youtu.be/3YyKv9AAl5o</oembed>


#### Заключение:

1. Хочется выразить благодарность командам разработчиков: Openshift/Kubernetes, Openstack, Kuryr. 
2. Решение получилось максимально простым, но при этом осталось гибким и функциональным.
3. Благодаря Openstack открылась возможность организовать тестирование на таких процессорных архитектурах как ARM и MIPS.


#### Интересное:

1. [Openshift и Windows Containers](https://www.youtube.com/watch?v=B0qqnnmcb9w)
2. [CRI-O поддерживает Clear Containers](http://cri-o.io/)