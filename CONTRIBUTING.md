## Development

```bash
cd ~/code
git clone git@github.com:kvz/frey.git
cd frey
npm install
npm link # Makes /usr/local/bin/frey point to ~/code/frey/bin/frey instead of the global install
```

## Converting HCL

```bash
bin/converter.sh tusd ~/code/infra-tusd/envs/production/infra.tf
``` 