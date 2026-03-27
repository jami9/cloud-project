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

L’objectif principal est de développer une **architecture distribuée** composée de plusieurs machines virtuelles permettant de gérer dynamiquement une infrastructure cloud via une interface graphique intuitive.

### Architecture

Le système repose sur trois composants principaux :

### 1️ API Gateway
- Point d’entrée principal du système  
- Centralisation des requêtes utilisateurs  
- Interface web dynamique  
- Gestion des actions :
  - Création de ressources
  - Suppression
  - Consultation

### 2️ Plateforme Cloud (OpenStack - MicroStack)
- Gestion des ressources IaaS :
  - Machines virtuelles
  - Réseaux
  - Stockage  
- Simulation d’un environnement cloud réel  

### 3️ Orchestrateur (OpenShift - OKD)
- Gestion des applications conteneurisées  
- Basé sur Kubernetes  
- Déploiement automatisé des applications  

---

## Fonctionnement global

Le système suit une **architecture orientée services** :

- L’utilisateur interagit uniquement avec l’interface de l’API Gateway  
- L’API Gateway communique avec :
  - OpenStack (IaaS)
  - OpenShift (PaaS)

### Fonctionnalités

- Création et suppression des machines virtuelles  
- Supervision de l’infrastructure  
- Déploiement d’applications conteneurisées  
- Gestion dynamique des ressources  

---

## Objectifs du projet

- Mettre en place une infrastructure cloud simulée  
- Développer une interface de gestion centralisée  
- Automatiser les tâches d’administration  
- Comprendre l’intégration entre IaaS et PaaS  
- Appliquer les concepts DevOps  

---

## Contraintes et choix techniques

- Ressources matérielles limitées (RAM)  
- Exécution **séquentielle des VMs**  
- Optimisation de l’utilisation des ressources  

Cette approche permet de simuler un environnement cloud réel avec des moyens limités.

---

## Technologies utilisées

- OpenStack (MicroStack)  
- OpenShift (OKD)  
- Kubernetes  
- API REST  
- Linux / Ubuntu Server  
- Virtualisation  

---

## Résultats attendus

- Plateforme de gestion centralisée  
- Automatisation du déploiement  
- Interface utilisateur intuitive  

---

## Conclusion

Ce projet représente une mise en pratique des concepts clés du cloud computing :

- Virtualisation  
- Orchestration  
- Automatisation  
- DevOps  

Il constitue une base solide pour travailler sur des infrastructures cloud professionnelles.

---

## Auteur

**Jamila Laouissi**  
Ingénieure en informatique – Infrastructure & Réseaux  

---

## Licence

Ce projet est réalisé dans un cadre académique.
