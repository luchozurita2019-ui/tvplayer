from pathlib import Path

path = Path('lib/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')
marker = "  @override\n  Widget build(BuildContext context) {\n"
start = text.rfind(marker)
if start < 0:
    raise SystemExit('PlayerScreen build marker not found')

new_tail = r'''  @override
  Widget build(BuildContext context) {
    final channel = widget.playlist[_currentIndex];
    final query = _channelListQuery.toLowerCase();
    final filteredChannels = query.trim().isEmpty
        ? widget.playlist
        : widget.playlist
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: LiveVideoView(
              key: ValueKey(channel.uniqueKey),
              player: _player,
              controller: _controller,
              canPrevious: _currentIndex > 0,
              canNext: _currentIndex < widget.playlist.length - 1,
              onPrevious: _previous,
              onNext: _next,
              isLiveContent: widget.isLiveContent,
              title: channel.name,
              subtitle: channel.group,
              logoUrl: channel.logoUrl,
              channelNumber: _currentIndex + 1,
              resolution:
                  _videoWidth == null || _videoHeight == null ? '' : _resolutionText,
              performanceLabel:
                  _lastStartupMs == null ? null : '$_lastStartupMs ms',
              onBack: () => Navigator.of(context).maybePop(),
              onShowChannelList: () =>
                  setState(() => _showChannelList = !_showChannelList),
              onShowStreamInfo: _showStreamInfo,
              onShowPerformance:
                  _lastStartupMs == null ? null : _showPerformanceInfo,
            ),
          ),
          if ((_isBuffering || _reconnecting) && _errorMessage == null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xC914202D),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _normalProbeFallbackUsed && _retryCount == 0
                              ? 'Probando modo compatible…'
                              : _reconnecting
                                  ? 'Reconectando (intento $_retryCount de $_maxAutoRetries)…'
                                  : _hasEverPlayed
                                      ? 'Recibiendo datos…'
                                      : 'Cargando…',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_errorMessage != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111B26),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () => unawaited(_playCurrent()),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _showChannelList = true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.view_list_rounded),
                              label: const Text('Ver otros canales'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _showChannelList ? 0 : -370,
            width: 370,
            child: Material(
              elevation: 18,
              color: const Color(0xF2071728),
              child: SafeArea(
                left: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.live_tv_rounded,
                            color: Color(0xFF58A6FF),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Canales',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () =>
                                setState(() => _showChannelList = false),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar canal…',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF1677FF),
                            ),
                          ),
                          isDense: true,
                        ),
                        onChanged: (value) =>
                            setState(() => _channelListQuery = value),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredChannels.length,
                        itemBuilder: (context, index) {
                          final c = filteredChannels[index];
                          final realIndex = widget.playlist.indexOf(c);
                          final isCurrent = realIndex == _currentIndex;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF1677FF)
                                      .withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: isCurrent
                                  ? Border.all(
                                      color: const Color(0xFF1677FF)
                                          .withValues(alpha: 0.35),
                                    )
                                  : null,
                            ),
                            child: ChannelTile(
                              channel: c,
                              isFavorite: false,
                              onFavoriteToggle: () {},
                              onTap: () => _switchToChannel(realIndex),
                              allowNetworkArtwork: false,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
'''

path.write_text(text[:start] + new_tail, encoding='utf-8')
print('Premium PlayerScreen UI applied')
