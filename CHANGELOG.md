# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

## [Unreleased]

- Nenhuma mudança planejada para o próximo lançamento ainda.

## [3.0.0] - 2025-11-21

### Lançamento: A Era da Instalação Automática

Esta versão marca uma grande mudança na forma como os usuários interagem com a Limpeza Avançada. O foco foi simplificar a instalação e o uso diário, tornando a ferramenta acessível com um único duplo-clique.

### Adicionado
- **Script de Instalação Dedicado:** Um novo script (`Instalar.ps1`) que automatiza toda a configuração inicial.
- **Criação Automática de Atalho:** O instalador agora cria um atalho na área de trabalho do usuário para acesso rápido e fácil.
- **Ícone Personalizado:** O atalho agora utiliza um ícone visualmente atraente (`.ico`) que é baixado automaticamente do repositório durante a instalação.
- **Atualização Automática de Ícones:** Implementada uma função que força a atualização da área de trabalho para garantir que o ícone personalizado seja exibido corretamente após a instalação.
- **Execução Totalmente Oculta:** A execução a partir do atalho agora é feita de forma completamente silenciosa, sem nenhuma janela do PowerShell visível para o usuário.

### Alterado
- **Método de Instalação:** O processo de instalação foi completamente redesenhado para ser mais amigável, removendo a necessidade de configuração manual de aliases.
- **Experiência de Usuário:** A ferramenta agora se comporta mais como um aplicativo instalado do que um simples script.

### Removido
- **Alias `limpeza` do PowerShell:** O alias de terminal foi removido para simplificar a instalação e focar na experiência via atalho na área de trabalho. O método de execução via terminal ainda é possível, mas não é mais configurado automaticamente.

### Corrigido
- **Problema de Exibição do Ícone:** Corrigido o problema onde o ícone personalizado não aparecia no atalho da área de trabalho após a criação, implementando a atualização forçada do cache de ícones do Windows.

## [2.1.0] - 2025-11-13

### Adicionado
- **Interface Gráfica (GUI) completa:** Introdução de uma interface moderna construída com Windows Forms para guiar o usuário.
- **Barra de Progresso em Tempo Real:** Implementação de uma barra de progresso detalhada, mostrando a etapa atual, o percentual e o tempo estimado.
- **Relatório Final Detalhado:** Geração de um relatório completo ao final da limpeza, que pode ser salvo em arquivo `.txt`.
- **Limpeza de Logs de Eventos:** Adicionada a funcionalidade de limpar os logs de eventos do Windows (Aplicativo, Sistema, Segurança).

### Alterado
- **Solicitação de Elevação:** O script agora solicita privilégios de administrador de forma mais elegante através da interface gráfica.

## [2.0.0] - 2025-11-10

### Adicionado
- **Limpeza Abrangente:** Versão inicial com limpeza de pastas temporárias, cache do Windows Update, lixeira e caches de múltiplos navegadores (Edge, Chrome, Firefox).
- **Segurança e Validação:** Adicionadas verificações para garantir que o script seja executado com privilégios de administrador para acesso completo ao sistema.
- **Mensagens Claras:** Implementação de `Write-Host` com cores para melhorar a legibilidade da saída no terminal.

[Unreleased]: https://github.com/edgardocorrea/LimpezaAvancada/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/edgardocorrea/LimpezaAvancada/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/edgardocorrea/LimpezaAvancada/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/edgardocorrea/LimpezaAvancada/releases/tag/v2.0.0