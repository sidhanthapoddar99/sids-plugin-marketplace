How to setup








what i use 

mise
docker and docker compose
claude.md 
uv preffered of direct pip
bun preferred of npm or yarn 
rust 
go

my self created tool https://github.com/sidhanthapoddar99/uvenv
/home/sid/projects/02_OpenSource/02_dev_tools/uvenv/ -- check this one out

frontend 
- vite : high hidration 
- next JS
- astro
- nginx for static file serving
- already have traefik -- managed using dynmic configuration so just need to network 


case of workflow 
- development and app building
    for python use ./venv project level use requirements.txt  and uv pip install ...
- ml workflows : usse uvenv to manage multiple golabl envs but do create requirement txt
- mise is a must for both





this is not exactly a monorepo setup but more of a general setup for my projects


When we are creating mono Repo. We do need to consider the fact that we have a single environment variable outside. Of all the repose like inside a single mono repo. We would have folders for back end, front end databases


when developing we dont put secrete in the config files
we have a single config file which takes the secretes of dynamic configuration from env variables. 
configsin yaml with option to take from env as {{VAR_NAME}} or something like ${VAR_NAME}

eg 

/backed
    - main.py
    - requirements.txt
    - config.yaml
/fronted
    - index.html
    - main.js
    - package.json use dotenv

/database # have a .gitkeep file here to keep the folder in the repo but not the actual database files
    - postgres
    - mongodb
    - redis
    - neo4j/kuzu
    - seaweed

.env

using sqlalchemy for database management and migrations


for frontend we are using
- typescript
- shadcn/ui for prebuilt components
- tailwind for styling
- Vite proxy server for development to avoid CORS issues and have a smooth development experience bu all backend paths have prefix of /api so that we can easily route the traffic in production as well. or it can be hosted on diff domain but need to setup cors. first is perffererd but in very some cases 2nd can be used as well. 
- when in prod nginx routes the traffic to backend based on the path.


for mobile app all native using 
- kotlin for android
- swift for ios

for deskop app using
- tauri with rust 
- electron 


- envs
- docker compose
- nginx 
- deployument vs development



Ideally we don't run the docker compose manually but have a script to do that for us. 
precofigured scripts



Documentation files

CICD options future
vault locations selfhosted and password settings when not using .env 
if projects are opensource have git actions


for ml workflows we may also use dstack and aws for model training and also dstack might be replaced with custom alternative as well


Vite + Typescript + ShadCn

UI guidelines

Modularity of code

main single script

.VScode debugger setup optional



using mise to manage multiple envs and dependencies for both python and js.

create a sub doc for this decision 

shell script setups 


not complete but partial examples are

all live in 




also check we have a docs folder in each of them that uses documenation enginge (also another code and you can access its skill as well to get more info)
for mono repo the docs lives in the repo itself under docs/
but in case of multiple repose we have a seperate repo for the docs



there are also projects which are not a single mono repo and instead require multiple repos 
like individual microservices or seperate frontend and backend repos 

in those case how do we manage 

the rules are still valid .envs for secrets, and shared vars like reletive urls etc





config.yaml
config.json 

when configs have some varialblility 

we can have 

config.local.yaml which gets precedence over config.yaml in both docker or local dep
config.local.json

yaml is preffered for configs because of its readability and support for comments but json can also be used if required. The main point is to have a single source of truth for configuration and


if the setting s




~/projects 


example 1: 06_04_NeuraSutra/neurasutra-api-management
to take
- .env and create .env.example
- how config and config templates are used and how they read from env variables
- scripts and how docker compose is used to run the project and also how docker use .env files
- use of sqlalchemy and how we manage database migrations using alembic
- frontend uses vite and how we use proxy for development and nginx for production
- how volumes are always mounted on this folder 
- if required we can sym link a common shared folder when deploying for prodserver. -- but that completely optional : we dont use docker volumne but only do colume mounts of abs paths


example 2: 02_OpenSource/04_knowledge_management/atheneum
- .env
- postgres not using alembic instead direct code and check reason wht alembic is not useful here for complex cases
- dev script
- mise
- multi backend
- frontend redirects vite proxy
- venv locations





example 3: 

/home/sid/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025/docker

really good example of how the docker compose are setup 
older versions used scripts but 
this verison uses go based tool to call docker comosie and manage it, This is a very niche use case. Because we are running multiple nodes of blockchain and testing it, so this won't occur up anytime but the structure of how the compose files are in a 1 single Folder of docker and subdivided again. And how each one of them overrides And use in conjecture to the other It's a really good example
/home/sid/projects/06_01_Chimere/Own-blockchain/chimere-chain-2025/Readme.md See the docker part. Or the cluster part? How we are using these scripts and what flags and effect does it have? On Docker Instead of Go script. In this we are running a go script because it does much more things and you wanted a consolidated Option and if in future we need a very complex. CLI orchestrator Then we can use Go as well. But in Other cases. A simple shell script could do what go does for docker
checkout the go code as well 



This is the general setup we are doing. Let's first discuss in detail. What's standard and what's not standard and what's the best industry practices? What's We can improve so this these flows are. Evolved overtime and each of them might not be perfect. As version bumps up. Or as we create this skill and. We have a defined structure. Even future would be easier on the mental model, because I have a lot of projects which I'm working on and having a similar kind of structure Across multiple mono repos would help me. 


If it's not a single project And like a company established Project Which has multiple backends, and. Has a couple of things. Then we can divide it into different git repositories as well And in those cases The env logic or the docker composed single docker compose logic might not work. So this is mostly for mono repo But also for setup, maybe for mono repo we can create have another Section And for this. Like for general we can have a section.



Note all these examples are not perfect as they were created at diffrent time and had their own requirements and constraints. But they are good examples to understand the general structure and flow of how we are managing our projects. As we evolve and create more projects, we can refine this structure and make it more robust and scalable.


for ML like workflows we also have global venv 

fetch the uvenv and understand what it does 

basically this plugin or skill is for managing and creating repos

we can have skills under it for managing and init slash commands as well that invoke the skill 

this can be used to setup multiple repos as well as well mono repo 

