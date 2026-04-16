# cloud-project
# Mise en place d’un cloud privé, sécurisé et automatisé pour le déploiement des infrastructures OSS d’Orange Tunisie

---

## Introduction

Ce projet s’inscrit dans le domaine du **Cloud Computing** et de l’**administration des infrastructures virtualisées**.  
Il a pour objectif de concevoir et de mettre en place une plateforme permettant la gestion centralisée d’une infrastructure cloud, en s’inspirant des architectures utilisées dans les environnements professionnels.

Avec l’évolution rapide des technologies cloud, les entreprises ont besoin de solutions capables d’**automatiser**, de **superviser** et de **simplifier** la gestion des ressources informatiques.  
Ce projet propose une approche basée sur l’intégration de plusieurs outils modernes afin de simuler un environnement cloud réel sur une infrastructure locale.

---

## Description du projet

L’objectif principal est de développer une **architecture distribuée** composée de plusieurs machines virtuelles permettant de gérer dynamiquement une infrastructure cloud via une interface graphique et une API centralisée.

---

## Architecture globale

Le système repose sur trois machines virtuelles principales :

### VM1 — Infrastructure Cloud (OpenStack MicroStack + Kubernetes + Terraform)
- Mise en place d’un cluster Kubernetes sur OpenStack (MicroStack)
- Provisioning automatique des ressources avec **Terraform**
- Gestion des ressources IaaS :
  - Machines virtuelles
  - Réseaux
  - Stockage
- Base de l’infrastructure cloud privée

---

### VM2 — Dashboard & API Gateway (Kong)
- Interface web de gestion du cloud
- API Gateway basée sur **Kong**
- Accès centralisé aux services OpenStack et Kubernetes
- Gestion des requêtes :
  - Création / suppression de ressources
  - Monitoring de l’infrastructure
- Communication avec VM1 via API sécurisée

---

### VM3 — Plateforme Orchestrateur (OpenShift OKD)
- Mise en place d’un cluster Kubernetes avec **OpenShift OKD**
- Déploiement et gestion des applications conteneurisées
- Orchestration des workloads
- Intégration dans l’infrastructure MicroStack

---

## Fonctionnement global

L’architecture suit un modèle **cloud hybride et distribué** :

- L’utilisateur interagit uniquement avec le **Dashboard (VM2)**
- Le Dashboard passe par l’API Gateway **Kong**
- Les requêtes sont redirigées vers :
  - VM1 (OpenStack + Kubernetes + Terraform)
  - VM3 (OpenShift OKD)

---

## Partie 1 du projet

La première partie consiste à :

- Déployer un **cluster Kubernetes sur VM1**
- Utiliser **OpenStack MicroStack** comme infrastructure cloud
- Automatiser le provisioning avec **Terraform**
- Accéder à l’infrastructure via le **dashboard (VM2)**
- Centraliser les appels API via **Kong Gateway**

Objectif : construire une infrastructure cloud IaaS fonctionnelle et automatisée.

---

## Partie 2 du projet

La deuxième partie consiste à :

- Déployer une **VM3 dédiée à OpenShift OKD**
- Créer un cluster Kubernetes avec OpenShift
- Intégrer OpenShift dans l’infrastructure MicroStack
- Permettre le déploiement d’applications conteneurisées
- Tester l’orchestration et la gestion des workloads

Objectif : ajouter une couche PaaS complète à l’architecture cloud.

---

## Objectifs du projet

- Mettre en place une infrastructure cloud complète (IaaS + PaaS)
- Automatiser le déploiement des ressources
- Développer une interface de gestion centralisée
- Comprendre l’intégration Kubernetes / OpenStack / OpenShift
- Appliquer les principes DevOps et Cloud Computing

---

## Contraintes et choix techniques

- Ressources matérielles limitées (RAM et CPU)
- Utilisation de plusieurs VMs sur une seule infrastructure
- Optimisation des déploiements
- Architecture distribuée simulée en environnement local

---

## Technologies utilisées

- OpenStack (MicroStack)
- Terraform
- Kubernetes
- OpenShift OKD
- Kong API Gateway
- REST APIs
- Linux / Ubuntu Server
- Virtualisation

---

## Résultats attendus

- Infrastructure cloud hybride fonctionnelle
- Dashboard centralisé de gestion
- Automatisation complète des déploiements
- Intégration OpenStack + Kubernetes + OpenShift
- Architecture proche des environnements professionnels

---

## Conclusion

Ce projet permet de mettre en pratique les concepts fondamentaux du cloud computing :

- Virtualisation
- Orchestration
- Automatisation
- Infrastructure as Code
- DevOps

Il constitue une architecture complète représentant un environnement cloud moderne et évolutif.

---

## Auteur

**Jamila Laouissi**  
Ingénieure en informatique – Infrastructure & Réseaux  

---

## Licence

Projet académique réalisé dans un cadre de formation.
