# ✦ KALAKRITI

### From Voice to Product — A Digital Workflow for Artisans.

> **KALAKRITI** is an AI-powered artisan commerce platform that transforms a simple voice description into a polished, multilingual product listing — with intelligent pricing, image enhancement, cart management, and a cloud-backed marketplace workflow.

**Built for artisans. Designed for simplicity. Powered by AI.**

---

<p align="center">

[![React](https://img.shields.io/badge/React-18-61DAFB?style=for-the-badge&logo=react&logoColor=white)](https://react.dev/)
[![Vite](https://img.shields.io/badge/Vite-Frontend-646CFF?style=for-the-badge&logo=vite&logoColor=white)](https://vitejs.dev/)
[![FastAPI](https://img.shields.io/badge/FastAPI-Backend-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Gemini](https://img.shields.io/badge/Gemini-AI-8E75B2?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev/)

</p>

---

## ◈ THE IDEA

Traditional artisans often have the skill to create beautiful products — but turning those creations into professional online listings can be difficult.

**KALAKRITI bridges that gap.**

```text
       🎙️ SPEAK
          │
          ▼
   ┌───────────────┐
   │ Voice Input   │
   └───────┬───────┘
           │
           ▼
   🤖 AI UNDERSTANDS
           │
           ▼
   ┌─────────────────────┐
   │ Product Description │
   │ English + Hindi     │
   └──────────┬──────────┘
              │
              ▼
       💰 SMART PRICING
              │
              ▼
       🖼️ IMAGE ENHANCE
              │
              ▼
       🛍️ PRODUCT LISTING
              │
              ▼
       ☁️ CLOUD DATABASE
┌──────────────────────────────────────────────────────────────┐
│                     👤 USER / ARTISAN                        │
│                    Mobile / Desktop Browser                  │
└─────────────────────────────┬────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    LAYER 1 · FRONTEND                        │
│                                                              │
│  React 18 · Vite · Tailwind/CSS · Axios · React Router      │
│  Context API · JWT · Canvas API · Web Speech API            │
│                                                              │
│             🧠 Browser-Side AI / Processing                  │
│       Background Removal · Voice → Text · Image Canvas      │
└─────────────────────────────┬────────────────────────────────┘
                              │
                       HTTPS / JSON
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    LAYER 2 · BACKEND                         │
│                                                              │
│       FastAPI · Python 3.11+ · Uvicorn · Pydantic           │
│       SQLAlchemy · JWT · Passlib · CORS                     │
│                                                              │
│                🧠 Server-Side AI                             │
│                    Gemini API                                │
└───────────────┬──────────────────────┬───────────────────────┘
                │                      │
                │ SQL                  │ HTTPS
                ▼                      ▼
┌──────────────────────────┐    ┌──────────────────────────────┐
│   LAYER 3 · DATABASE     │    │    LAYER 4 · AI SERVICES     │
│                          │    │                              │
│   PostgreSQL 16          │    │       Google Gemini          │
│   Neon Serverless        │    │       Text Generation        │
│                          │    │                              │
│   users                  │    │   • Description Generator    │
│   products               │    │   • Pricing Assistant       │
│   carts                  │    │   • Multilingual Content     │
│   cart_items             │    │                              │
└──────────────────────────┘    └──────────────────────────────┘
                │
                │
                ▼
┌──────────────────────────────────────────────────────────────┐
│                  LAYER 5 · DEPLOYMENT                        │
│                                                              │
│      Frontend → Render / Vercel / Netlify                   │
│      Backend  → Render                                      │
│      Database → Neon                                         │
└──────────────────────────────────────────────────────────────┘
Technology	Purpose
JavaScript ES6+	Application logic
React 18	UI architecture
Vite	Development & production build
HTML5 / JSX	Structure
CSS3 / Tailwind CSS	Styling
Axios	HTTP communication
React Router v6	Navigation
React Context API	Global state
localStorage	JWT persistence
                    USER DEVICE
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
      🖼️ IMAGE       🎙️ VOICE       🖌️ CANVAS
      PROCESSING     RECOGNITION     PROCESSING
          │              │              │
          ▼              ▼              ▼
       WASM           WEB SPEECH       BROWSER
       ENGINE            API            CANVAS
◈ LAYER 02 — BACKEND
The Intelligence & Business-Logic Layer
Built with Python + FastAPI, the backend acts as the central orchestration layer between the frontend, database, and external AI services.

Stack
Python 3.11+
      │
      ├── FastAPI
      ├── Uvicorn
      ├── Pydantic v2
      ├── SQLAlchemy 2.0
      ├── psycopg2-binary
      ├── python-jose
      ├── passlib[bcrypt]
      ├── python-dotenv
      └── FastAPI CORSMiddleware

Backend Responsibilities
Frontend
   │
   ├── Authentication
   ├── Product Management
   ├── Cart Operations
   ├── AI Requests
   └── User Data
          │
          ▼
      FASTAPI
          │
     ┌────┴────┐
     ▼         ▼
 Database    Gemini

The backend handles:

🔐 JWT authentication

👤 User management

🛍️ Product operations

🛒 Cart management

🤖 AI orchestration

🗄️ Database operations

🌐 CORS/API configuration

◈ LAYER 03 — DATABASE
PostgreSQL · Neon · Serverless
KALAKRITI uses PostgreSQL 16 as its relational database, hosted on Neon.

                 PostgreSQL
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼
     users        products       carts
                                   │
                                   ▼
                              cart_items

Database Schema
users
id
email
password
name
role
created_at

products
id
user_id
title
description
price
image_url
category
created_at

carts
id
user_id
created_at

cart_items
id
cart_id
product_id
quantity

Database Connection
Application
     │
     │ DATABASE_URL
     ▼
Neon PostgreSQL
     │
     └── SSL Required

The database schema is automatically created through SQLAlchemy during application startup.

◈ LAYER 04 — AI ENGINE
🧠 Google Gemini
KALAKRITI uses Gemini primarily for text intelligence, keeping computationally expensive or unnecessary AI workloads away from the server.

AI WORKFLOW #01 — MULTILINGUAL CATALOGER
🎙️ Artisan speaks
        │
        ▼
   Web Speech API
        │
        ▼
  Voice Transcript
        │
        ▼
     FastAPI
        │
        ▼
    Gemini API
        │
        ├───────────────┐
        ▼               ▼
   SEO Title       Description
   English/Hindi   English/Hindi

Input
Voice transcript
+
Product context

Output
🇬🇧 English title
🇬🇧 English description

🇮🇳 Hindi title
🇮🇳 Hindi description

💰 AI WORKFLOW #02 — PRICING ASSISTANT
The pricing assistant takes contextual information about a product and generates a suggested selling price.

Product Description
        +
Product Category
        +
Material Cost
        │
        ▼
    Gemini API
        │
        ▼
┌──────────────────────┐
│ Suggested Price INR  │
│ + Reasoning          │
└──────────────────────┘

Important Design Choice
Gemini is not responsible for everything.

              AI RESPONSIBILITIES

        ┌─────────────┴─────────────┐
        │                           │
     BROWSER                     SERVER
        │                           │
        ▼                           ▼
 Image Processing              Gemini API
 Voice → Text                       │
 Canvas Processing                  ├── Description
                                    └── Pricing

This keeps the architecture lightweight and avoids unnecessary API usage.

◈ AI FEATURE MAP
Feature	Runs Where	Technology	Purpose
🖼️ Image Enhancer	Browser	@imgly/background-removal	Background removal / enhancement
🎙️ Voice Input	Browser	Web Speech API	Voice → Text
✍️ AI Cataloger	Backend	Gemini API	Generate product content
🌐 Multilingual Content	Backend	Gemini API	English + Hindi
💰 Pricing Assistant	Backend	Gemini API	Price suggestion
🖌️ Image Preview	Browser	Canvas API	Preview / manipulation

◈ LAYER 05 — DEPLOYMENT
The entire platform is designed around low-cost cloud infrastructure.

                    🌍 INTERNET
                         │
          ┌──────────────┴──────────────┐
          │                             │
          ▼                             ▼
     FRONTEND                       BACKEND
   Render / Vercel                  Render
          │                             │
          │                             ├──────► Gemini API
          │                             │
          │                             ▼
          │                         Neon DB
          │
          └──────── HTTPS ───────────────┘

Deployment Stack
Component	Platform
Frontend	Render / Vercel / Netlify
Backend	Render
Database	Neon
AI	Google Gemini
Domain	Custom / Platform subdomain

Environment Variables
DATABASE_URL=...
GEMINI_API_KEY=...
JWT_SECRET=...

🔐 Secrets should never be committed to the repository.

◈ END-TO-END WORKFLOW
Here's what happens when an artisan creates a product:

01  👤 USER
    │
    │ Speaks about their product
    ▼

02  🎙️ WEB SPEECH API
    │
    │ Voice → Text
    ▼

03  ⚛️ REACT FRONTEND
    │
    │ Sends transcript
    ▼

04  ⚡ FASTAPI
    │
    │ Validates request
    ▼

05  🧠 GEMINI
    │
    ├── Generates title
    ├── Generates description
    └── Translates content
    ▼

06  💰 PRICING ASSISTANT
    │
    │ Product + category + material cost
    ▼

07  🧠 GEMINI
    │
    │ Suggested INR price
    ▼

08  🖼️ IMAGE PROCESSOR
    │
    │ Browser-side background removal
    ▼

09  🛍️ PRODUCT LISTING
    │
    │ Save product
    ▼

10  🐘 POSTGRESQL
    │
    │ Persistent cloud storage
    ▼

11  ✨ MARKETPLACE

◈ SECURITY FLOW
Authentication uses JWT-based authentication.

              LOGIN
                │
                ▼
         FastAPI Backend
                │
                ▼
       Verify credentials
                │
                ▼
            JWT Token
                │
                ▼
        Browser localStorage
                │
                ▼
        Authorization Header
                │
                ▼
        Protected API Routes

Example:

Authorization: Bearer <JWT>

Passwords are protected using bcrypt-based hashing rather than storing plaintext passwords.

◈ WHY THIS ARCHITECTURE?
KALAKRITI intentionally separates responsibilities.

┌──────────────────────────────────────────┐
│             RESPONSIBILITY               │
├──────────────────────────────────────────┤
│ UI              → React                  │
│ Build           → Vite                   │
│ API             → FastAPI                │
│ Validation      → Pydantic               │
│ ORM             → SQLAlchemy             │
│ Database        → PostgreSQL             │
│ Authentication  → JWT + bcrypt           │
│ Voice           → Web Speech API          │
│ Image AI        → Browser/WASM            │
│ Text AI         → Gemini                  │
│ Hosting         → Render / Vercel        │
│ Database Cloud  → Neon                   │
└──────────────────────────────────────────┘

The result is a system that is:

Modular · Lightweight · Mobile-friendly · AI-assisted · Cloud-ready

◈ TECH STACK
Frontend
React 18
Vite
JavaScript ES6+
HTML5
JSX
CSS3
Tailwind CSS
Axios
React Router v6
Context API

Browser Intelligence
@imgly/background-removal
Web Speech API
Canvas API
WebAssembly

Backend
Python 3.11+
FastAPI
Uvicorn
Pydantic v2
SQLAlchemy 2.0
psycopg2-binary
python-jose
passlib[bcrypt]
python-dotenv

AI
Google Gemini
google-generativeai

Database
PostgreSQL 16
Neon

Deployment
Render
Vercel
Netlify
Neon

◈ PROJECT PHILOSOPHY
AI should remove friction — not add complexity.
KALAKRITI follows three principles:

01 · LOCAL FIRST
Use the user's device whenever possible.

Image processing → Browser

Voice recognition → Browser

This reduces server dependency and unnecessary infrastructure cost.

02 · AI WHERE IT MATTERS
Use cloud AI for tasks that genuinely benefit from language reasoning.

Descriptions → Gemini

Translations → Gemini

Pricing assistance → Gemini

03 · SIMPLE FOR THE USER
Behind the scenes:

React
   +
FastAPI
   +
PostgreSQL
   +
Gemini
   +
WASM

But for the artisan:

Speak → Enhance → Publish

◈ COST-CONSCIOUS AI
The platform is designed around a low-cost / free-tier-friendly architecture.

                 COMPUTATION
                      │
          ┌───────────┴───────────┐
          │                       │
       LOCAL                    CLOUD
          │                       │
          ▼                       ▼
    Image Processing          Gemini
    Voice Recognition         Text AI
    Canvas                    Pricing
          │                       │
          └──────────┬────────────┘
                     ▼
               LOWER SERVER
                  LOAD

Instead of sending every operation to a server, KALAKRITI performs suitable tasks directly in the browser.

◈ COMMUNICATION BETWEEN LAYERS
                         👤 USER
                           │
                           │
                           ▼
                ┌─────────────────────┐
                │   ⚛️ REACT FRONTEND │
                │       + VITE        │
                └──────────┬──────────┘
                           │
                           │ HTTPS
                           │ Axios / JSON
                           │ JWT Header
                           ▼
                ┌─────────────────────┐
                │   ⚡ FASTAPI        │
                │   Python Backend    │
                └────────┬─────┬──────┘
                         │     │
                   SQL   │     │ HTTPS
                         │     │
                         ▼     ▼
              ┌────────────┐  ┌──────────────┐
              │ PostgreSQL │  │ Gemini API   │
              │   Neon     │  │ Google AI    │
              └────────────┘  └──────────────┘

Communication Flow
React
  │
  │ Axios
  ▼
FastAPI
  │
  ├──────────────► PostgreSQL
  │
  └──────────────► Gemini API

◈ COMPLETE AI MAP
                         🧠 KALAKRITI AI
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
         🖼️ IMAGE          🎙️ VOICE         ✍️ TEXT
         ENHANCER          INPUT             GENERATOR
              │                │                │
              ▼                ▼                ▼
        Browser/WASM      Web Speech       Gemini API
              │                │                │
              │                │        ┌───────┴───────┐
              │                │        │               │
              │                │        ▼               ▼
              │                │   Description      Pricing
              │                │   Generator        Assistant
              │                │
              └────────────────┴───────────────────────┘

◈ PROJECT HIGHLIGHTS
🎨 Artisan-first workflow

🎙️ Voice-powered product creation

🌐 Multilingual product cataloging

🧠 Gemini-powered content generation

💰 AI-assisted pricing

🖼️ Browser-side image processing

📱 Mobile-friendly architecture

🔐 JWT authentication

🛒 Shopping cart system

☁️ Serverless PostgreSQL

⚡ FastAPI backend

🚀 Cloud-ready deployment

💸 Free-tier-friendly infrastructure

◈ PROJECT REPOSITORY
Source Code
KALAKRITI

https://github.com/kurasidhartha/KALAKRITI

✦ KALAKRITI
Crafted by hands. Enhanced by technology.

A workflow where traditional craftsmanship meets modern AI — turning an artisan's voice into a digital storefront.

        🎨 CREATE
           ↓
        🎙️ SPEAK
           ↓
        🧠 UNDERSTAND
           ↓
        ✨ ENHANCE
           ↓
        💰 PRICE
           ↓
        🛍️ PUBLISH

KALAKRITI — WHERE CRAFT MEETS CODE.
<p align="center">
✦ Built with React • FastAPI • PostgreSQL • Gemini ✦
Made for artisans. Built with technology.

</p> ```

ChatGPT is AI and can make mistakes.

