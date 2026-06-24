# Melvin PETIT : Dockeriser une app Python

## Step 1 (~30mn) : Faire un **fork** public de l'application, sur votre propre compte Gitlab

J'ai forké le projet sur mon compte gitlab :
https://gitlab.com/WhiteMuush/melvin-petit-simplon-22-pyweb

## Step 2 (~30mn) : `git clone` le nouveau repository sur votre machine (VM, WSL, Mac)

J'ai créé une clé ssh nommée `gitlab`, j'ai copié la clé publique sur mon compte gitlab, j'ai cloné le repo en ssh.

## Step 3 (~15mn) : Installer Python sur votre machine

Python3 était déjà installé sur mon wsl :

```bash
$ python3 --version
Python 3.12.3
```

## Step 5 (~15mn) : Lancer l'application sur son PC, sans docker (`python app.py`)

L'application se lance correctement, montrant une page blanche avec écrit "hello, world!".

## Step 6 (~30mn) : Accéder à l'application depuis votre navigateur, puis explorer les logs générés dans le dossier `data`

```bash
$ cd data
$ ls
access.log
$ cat access.log
172.26.176.1 - [2026-06-23 09:29:05] - GET / HTTP/1.1
```

## Step 7 : Apprécier ce moment où tout fonctionne, car il ne va pas durer

SYMPA !

## Step 8 (~3h) : Écrire un `Dockerfile` qui décrira l'image Docker de notre application, première étape cruciale de la conteneurisation !

https://www.geeksforgeeks.org/python/setting-up-docker-for-python-projects-a-step-by-step-guide/

```bash
docker build -t python-app .
docker run -p 8080:8080 python-app:latest
```

Accessible sur `localhost:8080`.

Pour le volume :

```bash
$ docker ps
CONTAINER ID   IMAGE               COMMAND                  CREATED         STATUS         PORTS                                         NAMES
ef2f74677880   python-app:latest   "python app.py host=…"   6 minutes ago   Up 5 minutes   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp   charming_jang

$ docker exec -it ef2f74677880 sh
$ ls
app  app.py  data  requirements.txt
$ cd data
$ ls
access.log
$ cat access.log
172.17.0.1 - [2026-06-23 08:33:21] - GET / HTTP/1.1
172.17.0.1 - [2026-06-23 08:33:22] - GET / HTTP/1.1
172.17.0.1 - [2026-06-23 08:33:22] - GET / HTTP/1.1
172.17.0.1 - [2026-06-23 08:33:22] - GET / HTTP/1.1
172.17.0.1 - [2026-06-23 08:33:24] - GET / HTTP/1.1
```

## Step 10 (~1h30) : Écrire un Makefile pour les commandes ci-dessus (voir le barème)

Un Makefile permet d'effectuer ces étapes sans effort. Commandes attendues :

- `make run` : pour lancer l'application de 0 (`docker run`)
- `make build` : pour construire l'image (`docker build`)
- `make restart` : pour redémarrer l'application, sans perte de données !! (`docker stop` + `docker start`)
- `make kill` : pour arrêter et supprimer les conteneurs entièrement, AVEC perte de données (`docker rm` + `docker volume rm`)

J'ai fait toutes les demandes. Pour éviter de faire un retour dans la console à chaque fois, j'envoie le retour dans `/dev/null`, remplacé le retour par un `if/else` qui permettra d'avoir un message clair et précis. Pour les erreurs, elles sont retournées telles quelles pour avoir une trace plus simple à débuger.

## GitLab CI

Je l'ai fait sur un seul job, build run & test. On utilise la dernière version de docker actuelle sans utiliser `latest` par règle de sécurité. Le service docker-in-docker car le runner tourne sur un docker, donc il faut un système pour exécuter du docker dans du docker.
