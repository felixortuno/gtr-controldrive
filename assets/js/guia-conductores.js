(() => {
  const video = document.getElementById('demo-video');
  const chapters = document.getElementById('video-chapters');
  const status = document.getElementById('video-status');
  // The chapter timestamps are generated alongside the narrated MP4.
  const chapterData = [{"title":"Una jornada con la app","start":0},{"title":"Entrar y confirmar el camión","start":13.5},{"title":"Tu jornada y los cambios de camión","start":29.5},{"title":"Repostar","start":43.5},{"title":"Servicios, tickets y taller","start":65},{"title":"Orden de transporte","start":91.5},{"title":"Cerrar el día","start":106.5},{"title":"Tu nota y tus monedas","start":121.5},{"title":"Documentos","start":143},{"title":"El siguiente paso","start":159}]; // VIDEO_CHAPTERS
  const formatTime = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
  chapterData.forEach(({title, start}) => {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.start = start;
    const time = document.createElement('time');
    time.textContent = formatTime(start);
    time.dateTime = `PT${start}S`;
    const label = document.createElement('span');
    label.textContent = title;
    button.append(time, label);
    button.addEventListener('click', async () => {
      status.textContent = '';
      try {
        video.currentTime = start;
        await video.play();
        video.scrollIntoView({block:'center', behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});
      } catch {
        status.textContent = 'Pulsa el botón de reproducción del vídeo para continuar.';
      }
    });
    item.append(button);
    chapters.append(item);
  });
  video.addEventListener('timeupdate', () => {
    const active = chapterData.findLastIndex(chapter => chapter.start <= video.currentTime);
    chapters.querySelectorAll('button').forEach((button, index) => {
      if (index === active) button.setAttribute('aria-current', 'true');
      else button.removeAttribute('aria-current');
    });
  });
  video.addEventListener('error', () => {
    status.textContent = 'No se ha podido cargar el vídeo. Puedes descargar el MP4 o leer la explicación de debajo.';
  });
})();
