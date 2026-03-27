import { type Component, onMount, onCleanup } from "solid-js";
import * as THREE from "three";

const ThreeScene: Component = () => {
  let containerRef: HTMLDivElement | undefined;
  let renderer: THREE.WebGLRenderer | undefined;
  let scene: THREE.Scene | undefined;
  let camera: THREE.PerspectiveCamera | undefined;
  let animationId: number | undefined;

  const initThreeJS = () => {
    if (!containerRef) return;

    // Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x1a1a1a);

    // Camera
    const aspect = containerRef.clientWidth / containerRef.clientHeight;
    camera = new THREE.PerspectiveCamera(75, aspect, 0.1, 1000);
    camera.position.z = 5;

    // Renderer
    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(containerRef.clientWidth, containerRef.clientHeight);
    containerRef.appendChild(renderer.domElement);

    // Add a simple cube for testing
    const geometry = new THREE.BoxGeometry(1, 1, 1);
    const material = new THREE.MeshBasicMaterial({ color: 0x00ff00 });
    const cube = new THREE.Mesh(geometry, material);
    scene.add(cube);

    // Animation loop
    const animate = () => {
      animationId = requestAnimationFrame(animate);

      if (cube) {
        cube.rotation.x += 0.01;
        cube.rotation.y += 0.01;
      }

      if (renderer && scene && camera) {
        renderer.render(scene, camera);
      }
    };
    animate();
  };

  const cleanup = () => {
    if (animationId) {
      cancelAnimationFrame(animationId);
    }
    if (renderer && containerRef) {
      containerRef.removeChild(renderer.domElement);
      renderer.dispose();
    }
  };

  onMount(() => {
    initThreeJS();
  });

  onCleanup(() => {
    cleanup();
  });

  // Handle window resize
  const handleResize = () => {
    if (renderer && camera && containerRef) {
      const width = containerRef.clientWidth;
      const height = containerRef.clientHeight;
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height);
    }
  };

  window.addEventListener('resize', handleResize);

  return (
    <div
      ref={containerRef}
      class="three-scene-container"
      style={{
        width: '100%',
        height: '100%',
        position: 'relative'
      }}
    />
  );
};

export default ThreeScene;