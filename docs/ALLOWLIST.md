# Allowlist em nuvem (BNQQ Toolkit)

A versao publica nao usa mais `license.key`. Ela calcula o HWID da maquina e consulta uma Raw URL de Gist.

## 1. Criar o Gist privado

1. Abra https://gist.github.com.
2. Crie um arquivo chamado `allowlist.txt`.
3. Coloque um HWID por linha. Exemplo:

```text
8A47A9934CC1FE621C9D3072F091151CA8E736D6B552157E2A308959F84ED422
OUTRO_HWID_DE_TESTE
```

4. Marque o Gist como **Secret**.
5. Clique em **Create secret gist**.

## 2. Copiar a Raw URL

1. Abra o Gist criado.
2. Clique no botao **Raw** do arquivo `allowlist.txt`.
3. Copie a URL da barra de endereco. Ela deve comecar com:

```text
https://gist.githubusercontent.com/
```

Nao use a URL normal do Gist; use a Raw.

## 3. Configurar no script

Abra `bnqq.ps1` e procure a primeira linha de configuracao:

```powershell
$AllowlistUrl = "COLOQUE_SEU_LINK_AQUI"
```

Troque pelo link Raw:

```powershell
$AllowlistUrl = "https://gist.githubusercontent.com/SEU_USUARIO/SEU_ID/raw/allowlist.txt"
```

## 4. Compilar e testar

```powershell
cd C:\Users\bruno\Documents\GitHub\bnqq-toolkit
.\build.ps1
.\dist\BNQQ_Optimizer.exe
```

O executavel mostra o HWID se nao estiver autorizado. Adicione esse HWID no Gist, salve e abra o executavel novamente.

## 5. Enviar para os amigos

Cada amigo precisa:

1. Abrir o `BNQQ_Optimizer.exe`.
2. Copiar o HWID mostrado.
3. Enviar o HWID para voce.
4. Voce adiciona o HWID no Gist privado.
5. Ele abre o executavel novamente.

## Seguranca

- Nao torne o Gist publico.
- Nao coloque a lista de HWIDs em imagem ou chat publico.
- O Gist e apenas uma lista de HWIDs; nao coloque senhas ou chaves privadas.
- A URL Raw e publica para quem a tiver; o Gist Secret nao aparece na busca, mas quem tiver o link consegue ler.
- Allowlist nao substitui VBS/HVCI, Secure Boot ou TPM para anti-cheat.
