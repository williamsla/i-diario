$(function () {
  'use strict';

  var $modal = $('#tutorial-video-modal');
  var $iframe = $('#tutorial-video-frame');
  var $title = $('#tutorial-video-title');

  function withAutoplay(url) {
    if (!url) {
      return '';
    }

    return url.indexOf('?') >= 0 ? url + '&autoplay=1' : url + '?autoplay=1';
  }

  function openVideo(title, url) {
    if (!url) {
      return;
    }

    $title.text(title || '');
    $iframe.attr('src', withAutoplay(url));
    $modal.modal('show');
  }

  function clearVideo() {
    $iframe.attr('src', '');
  }

  $(document).on('click', '.js-open-tutorial-video', function (event) {
    event.preventDefault();

    var $card = $(this);
    openVideo($card.data('title'), $card.data('embed-url'));
  });

  $(document).on('keydown', '.js-open-tutorial-video', function (event) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      $(this).trigger('click');
    }
  });

  $modal.on('hidden.bs.modal', clearVideo);

  $(document).on('keydown', function (event) {
    if (event.key === 'Escape' && $modal.hasClass('in')) {
      $modal.modal('hide');
    }
  });
});
