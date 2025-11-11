# 🧹 Limpeza Avançada do Windows

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://microsoft.com/powershell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Author](https://img.shields.io/badge/Author-EdyOne-blueviolet.svg)](https://github.com/edgardocorrea)
[![Made with](https://img.shields.io/badge/Made%20with%20❤️-by%20EdyOne-red.svg)](https://github.com/edgardocorrea)

Uma programa desenvolvido em PowerShell para realizar uma limpeza profunda e otimização completa do sistema Windows. Desenvolvida com uma interface gráfica moderna e amigável para tornar a manutenção do PC uma tarefa simples e eficiente.

> **Repositório Oficial**: `github.com/edgardocorrea/LimpezaAvancada`

---

##  Instalação Rápida (Recomendado)

Para usar a Limpeza Avançada de forma prática e recorrente, execute o comando abaixo **uma única vez**. Ele irá configurar tudo para você, criando um **atalho na área de trabalho** e um **comando de atalho** no PowerShell.

### Passos para Instalar

1.  Abra o **PowerShell como Administrador**.
    - Clique no menu Iniciar, digite "PowerShell", clique com o botão direito em "Windows PowerShell" e selecione **"Executar como administrador"**.

2.  Copie e cole o comando abaixo e pressione **Enter**:

    ```powershell
    irm "https://raw.githubusercontent.com/edgardocorrea/LimpezaAvancada/Instalar/InstalarTudo.ps1" | iex
    ```

### Pronto! Agora você tem duas formas de executar:

- **Pela Área de Trabalho**: Basta dar um duplo-clique no ícone **"Limpeza Avançada by EdyOne"**.
- **Pelo Terminal**: Abra uma nova janela do PowerShell e digite `limpeza`.

> ** Nota de Segurança**: Execute o comando `irm ... | iex` apenas de fontes que você confia. Neste caso, você está confiando neste repositório oficial.

---

## Sobre o Projeto

Manter o Windows limpo e otimizado é essencial para garantir um desempenho rápido, estabilidade e mais espaço de armazenamento. Com o tempo, arquivos temporários, caches de navegadores, logs do sistema e outros dados desnecessários se acumulam, deixando o computador lento.

Este script automatiza todo o processo de limpeza, de forma segura e controlada, oferecendo ao usuário total visibilidade do que está sendo feito através de uma interface gráfica caprichada, com barra de progresso em tempo real e um relatório técnico detalhado ao final.

### Objetivo

O principal objetivo é **tornar a manutenção do Windows acessível a todos**, sem a necessidade de conhecimentos técnicos avançados. Com apenas alguns cliques, qualquer pessoa pode liberar gigabytes de espaço e melhorar a responsividade do seu sistema.

---

##  Principais Recursos

-  **Interface Gráfica Intuitiva**: Esqueça as linhas de comando complexas. Toda a operação é controlada por uma janela visual moderna.
-  **Barra de Progresso em Tempo Real**: Acompanhe o andamento de cada etapa da limpeza, com percentual e tempo estimado de conclusão.
-  **Limpeza Abrangente**: Verifica múltiplas fontes de sujeira:
  - Pastas temporárias do usuário e do sistema.
  - Cache do Windows Update.
  - Lixeira do Windows.
  - Cache de múltiplos navegadores (Edge, Chrome, Firefox, Brave, Vivaldi).
  - Logs de eventos do sistema.

---

##  Como Funciona

O fluxo de uso foi pensado para ser o mais simples possível:

1.  **Execução como Administrador**: O script solicita privilégios de administrador para acessar pastas do sistema.
2.  **Tela de Confirmação**: Uma janela personalizada e bonita informa ao usuário sobre a operação que será realizada, pedindo a confirmação para prosseguir.
3.  **Limpeza Automatizada**: Após a confirmação, a janela de progresso aparece e executa todas as etapas de limpeza de forma automática.
4.  **Acompanhamento em Tempo Real**: O usuário vê exatamente o que está sendo limpo, o espaço que está sendo liberado e quanto tempo falta.
5.  **Relatório Final**: Ao concluir, um relatório detalhado é exibido, permitindo ao usuário verificar o sucesso da operação podendo salvar o resultado.

---

##  Screenshots

> **Dica**: Para adicionar screenshots, hospede as imagens em um serviço como o Imgur e cole o link no formato abaixo:
> `![Tela de Confirmação](https://i.imgur.com/SUA_IMAGEM_1.png)`
> `![Barra de Progresso](https://i.imgur.com/SUA_IMAGEM_2.png)`
> `![Relatório Final](https://i.imgur.com/SUA_IMAGEM_3.png)`

---

##  Como Usar

Siga estes passos simples para executar a limpeza:

### Pré-requisitos

- Windows 10 ou Windows 11.
- PowerShell 5.1 ou superior (já vem instalado no Windows).
- Permissões de Administrador.

### Passo a Passo

1.  **Baixe o Script**: Faça o download do arquivo `LimpezaAvancada.ps1` deste repositório.
2.  **Execute como Administrador**:
    - Clique com o botão direito do mouse sobre o arquivo `LimpezaAvancada.ps1`.
    - Selecione a opção **"Executar com o PowerShell"**.
    - **Alternativamente**, para garantir os privilégios, clique com o botão direito e selecione **"Executar como Administrador"**.
3.  **Confirme a Limpeza**: Na janela de confirmação que aparecer, clique em **"Sim"** para iniciar.
4.  **Aguarde o Processo**: Acompanhe o progresso na tela. Não feche a janela enquanto a limpeza estiver em andamento.
5.  **Visualize o Relatório**: Ao final, o relatório será exibido. Você pode exportá-lo ou simplesmente fechá-lo.

---

## Informações Técnicas

- **Versão**: 2.1 - Edição Avançada
- **Linguagem**: PowerShell (.ps1)
- **Framework**: .NET (para a interface gráfica com Windows Forms)
- **Dependências**: Robocopy (nativo do Windows)

---

## Autor

Este projeto foi desenvolvido com dedição por **EdyOne**.

- **GitHub**: [edgardocorrea](https://github.com/edgardocorrea)
- **Repositório**: [edgardocorrea/LimpezaAvancada](https://github.com/edgardocorrea/LimpezaAvancada)

> *"Acredito que a tecnologia deve ser simples e ajudar as pessoas. Criei esta ferramenta para que qualquer um possa manter seu PC rápido e saudável sem complicações."* - EdyOne

---

##  Licença

Este projeto está licenciado sob a Licença MIT. Isso significa que você pode usá-lo, modificá-lo e distribuí-lo livremente. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

---

##  Agradecimentos

Um obrigado especial a toda a comunidade de desenvolvedores PowerShell e a todos os DEV´s que tornam a vida cada vez melhor!
